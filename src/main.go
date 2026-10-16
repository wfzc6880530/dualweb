package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"
)

const listenAddr = "127.0.0.1:9091"
const mihomoBase = "http://127.0.0.1:9090"
const maxBody = 8 << 20

type session struct{ expires time.Time }

var sessions = map[string]session{}
var sessMu sync.Mutex
var lastCPU struct {
	idle, total uint64
	at          time.Time
}
var cpuMu sync.Mutex
var httpClient = &http.Client{Timeout: 4 * time.Second}

type reply map[string]any

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}
func fail(w http.ResponseWriter, status int, msg string) { writeJSON(w, status, reply{"error": msg}) }
func randomHex(n int) string {
	b := make([]byte, n)
	if _, e := rand.Read(b); e != nil {
		return fmt.Sprintf("%d", time.Now().UnixNano())
	}
	return hex.EncodeToString(b)
}
func run(name string, args ...string) (string, error) {
	c := exec.Command(name, args...)
	var out bytes.Buffer
	c.Stdout = &out
	var er bytes.Buffer
	c.Stderr = &er
	e := c.Run()
	if e != nil {
		return strings.TrimSpace(out.String() + " " + er.String()), e
	}
	return strings.TrimSpace(out.String()), nil
}
func readFile(p string) string { b, _ := os.ReadFile(p); return strings.TrimSpace(string(b)) }
func writeFile(p, s string, mode os.FileMode) error {
	if e := os.MkdirAll(filepath.Dir(p), 0700); e != nil {
		return e
	}
	return os.WriteFile(p, []byte(s), mode)
}
func sameOrigin(r *http.Request) bool {
	o := r.Header.Get("Origin")
	if o == "" {
		return true
	}
	u, e := url.Parse(o)
	if e != nil {
		return false
	}
	return strings.EqualFold(u.Host, r.Host) && (u.Scheme == "http" || u.Scheme == "https")
}
func auth(w http.ResponseWriter, r *http.Request) bool {
	if !sameOrigin(r) {
		fail(w, 403, "跨站请求被拒绝")
		return false
	}
	c, e := r.Cookie("dualweb_session")
	if e != nil {
		fail(w, 401, "请先登录")
		return false
	}
	sessMu.Lock()
	defer sessMu.Unlock()
	s, ok := sessions[c.Value]
	if !ok || time.Now().After(s.expires) {
		delete(sessions, c.Value)
		fail(w, 401, "登录已过期，请重新登录")
		return false
	}
	return true
}
func bodyJSON(r *http.Request, v any) error {
	defer r.Body.Close()
	b, e := io.ReadAll(io.LimitReader(r.Body, maxBody+1))
	if e != nil {
		return e
	}
	if len(b) > maxBody {
		return errors.New("请求体过大")
	}
	d := json.NewDecoder(bytes.NewReader(b))
	d.DisallowUnknownFields()
	if e = d.Decode(v); e != nil {
		return e
	}
	var extra any
	if e = d.Decode(&extra); e != io.EOF {
		return errors.New("请求包含多余内容")
	}
	return nil
}
func route(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	if r.URL.Path == "/api/login" && r.Method == "POST" {
		var x struct {
			Password string `json:"password"`
		}
		if bodyJSON(r, &x) != nil || x.Password == "" {
			fail(w, 400, "请输入密码")
			return
		}
		stored := readFile("/etc/dualweb/password")
		if stored == "" || x.Password != stored {
			fail(w, 401, "密码错误")
			return
		}
		token := randomHex(32)
		sessMu.Lock()
		sessions[token] = session{time.Now().Add(8 * time.Hour)}
		sessMu.Unlock()
		http.SetCookie(w, &http.Cookie{Name: "dualweb_session", Value: token, Path: "/", HttpOnly: true, SameSite: http.SameSiteStrictMode, Secure: false, MaxAge: 28800})
		writeJSON(w, 200, reply{"ok": true})
		return
	}
	if !auth(w, r) {
		return
	}
	if r.URL.Path == "/api/logout" && r.Method == "POST" {
		if c, e := r.Cookie("dualweb_session"); e == nil {
			sessMu.Lock()
			delete(sessions, c.Value)
			sessMu.Unlock()
		}
		http.SetCookie(w, &http.Cookie{Name: "dualweb_session", Value: "", Path: "/", HttpOnly: true, SameSite: http.SameSiteStrictMode, MaxAge: -1})
		writeJSON(w, 200, reply{"ok": true})
		return
	}
	if r.URL.Path == "/api/connectivity" && r.Method == "GET" {
		connectivity(w)
		return
	}
	if r.URL.Path == "/api/status" && r.Method == "GET" {
		s, e := status()
		if e != nil {
			fail(w, 500, e.Error())
			return
		}
		writeJSON(w, 200, s)
		return
	}
	if r.URL.Path == "/api/password/change" && r.Method == "POST" {
		var x struct {
			Old string `json:"old"`
			New string `json:"new"`
		}
		if bodyJSON(r, &x) != nil || len(x.New) < 14 || len(x.New) > 128 {
			fail(w, 400, "新密码长度必须为 14–128 个字符")
			return
		}
		if x.Old != readFile("/etc/dualweb/password") {
			fail(w, 403, "旧密码错误")
			return
		}
		if writeFile("/etc/dualweb/password", x.New, 0600) != nil {
			fail(w, 500, "写入密码失败")
			return
		}
		_ = os.Remove("/root/dualweb-initial-password.txt")
		writeJSON(w, 200, reply{"ok": true})
		return
	}
	if r.URL.Path == "/api/wan/apply" && r.Method == "POST" {
		wanApply(w, r)
		return
	}
	if r.URL.Path == "/api/wan/confirm" && r.Method == "POST" {
		id := readFile("/tmp/dualweb-rollback-id")
		if id == "" {
			fail(w, 409, "没有待确认的 WAN 修改")
			return
		}
		_ = writeFile("/tmp/dualweb-confirm", id, 0600)
		_ = os.Remove("/tmp/dualweb-rollback-id")
		writeJSON(w, 200, reply{"ok": true})
		return
	}
	if strings.HasPrefix(r.URL.Path, "/api/proxy/") && r.Method == "POST" {
		action := strings.TrimPrefix(r.URL.Path, "/api/proxy/")
		if action != "start" && action != "stop" && action != "restart" {
			fail(w, 404, "未知操作")
			return
		}
		if _, e := run("/etc/init.d/nikki", action); e != nil {
			fail(w, 500, "Nikki 操作失败：请确认已安装 Nikki")
			return
		}
		writeJSON(w, 200, reply{"ok": true})
		return
	}
	if r.URL.Path == "/api/proxies" && r.Method == "GET" {
		mihomoGroups(w)
		return
	}
	if strings.HasPrefix(r.URL.Path, "/api/proxies/") && r.Method == "GET" {
		group := strings.TrimPrefix(r.URL.Path, "/api/proxies/")
		group, _ = url.PathUnescape(group)
		mihomoGroup(w, group)
		return
	}
	if r.URL.Path == "/api/select" && r.Method == "POST" {
		var x struct {
			Group string `json:"group"`
			Node  string `json:"node"`
		}
		if bodyJSON(r, &x) != nil || !validLabel(x.Group) || !validLabel(x.Node) {
			fail(w, 400, "策略组或节点名称无效")
			return
		}
		b, _ := json.Marshal(map[string]string{"name": x.Node})
		resp, e := mihomoRequest(http.MethodPut, "/proxies/"+url.PathEscape(x.Group), b)
		if e != nil {
			fail(w, 502, e.Error())
			return
		}
		defer resp.Body.Close()
		if resp.StatusCode < 200 || resp.StatusCode >= 300 {
			fail(w, 502, "Mihomo 拒绝切换节点，HTTP "+strconv.Itoa(resp.StatusCode))
			return
		}
		writeJSON(w, 200, reply{"ok": true})
		return
	}
	fail(w, 404, "接口不存在")
}
func validLabel(s string) bool {
	return s != "" && len(s) <= 160 && !strings.ContainsAny(s, "\r\n\x00")
}
func status() (reply, error) {
	out := reply{"hostname": "ImmortalWrt"}
	if b, e := os.ReadFile("/etc/openwrt_release"); e == nil {
		for _, line := range strings.Split(string(b), "\n") {
			if strings.HasPrefix(line, "DISTRIB_DESCRIPTION=") {
				out["version"] = strings.Trim(strings.TrimPrefix(line, "DISTRIB_DESCRIPTION="), "'\"")
			}
		}
	}
	if h, e := os.Hostname(); e == nil {
		out["hostname"] = h
	}
	if b, e := os.ReadFile("/proc/uptime"); e == nil {
		f := strings.Fields(string(b))
		if len(f) > 0 {
			n, _ := strconv.ParseFloat(f[0], 64)
			d := time.Duration(n) * time.Second
			out["uptime"] = fmt.Sprintf("%dd %02dh %02dm", int(d.Hours()/24), int(d.Hours())%24, int(d.Minutes())%60)
		}
	}
	if b, e := os.ReadFile("/proc/meminfo"); e == nil {
		vals := map[string]uint64{}
		for _, l := range strings.Split(string(b), "\n") {
			f := strings.Fields(l)
			if len(f) >= 2 {
				n, _ := strconv.ParseUint(f[1], 10, 64)
				vals[strings.TrimSuffix(f[0], ":")] = n
			}
		}
		total := vals["MemTotal"]
		avail := vals["MemAvailable"]
		if total > 0 {
			used := total - avail
			out["memory"] = fmt.Sprintf("%.0f%%", float64(used)*100/float64(total))
			out["memDetail"] = fmt.Sprintf("%.0f / %.0f MiB", float64(used)/1024, float64(total)/1024)
		}
	}
	out["cpu"] = cpuPercent()
	proto, _ := run("uci", "-q", "get", "network.wan.proto")
	wan := reply{"proto": proto, "up": false}
	if s, e := run("ubus", "call", "network.interface.wan", "status"); e == nil {
		var v struct {
			Up bool `json:"up"`
			L3 []struct {
				Address string `json:"address"`
			} `json:"ipv4-address"`
		}
		if json.Unmarshal([]byte(s), &v) == nil {
			wan["up"] = v.Up
			if len(v.L3) > 0 {
				wan["ip"] = v.L3[0].Address
			}
		}
	}
	for k, uciKey := range map[string]string{"username": "network.wan.username", "ipaddr": "network.wan.ipaddr", "netmask": "network.wan.netmask", "gateway": "network.wan.gateway"} {
		if v, e := run("uci", "-q", "get", uciKey); e == nil && v != "" {
			wan[k] = v
		}
	}
	if v, e := run("uci", "-q", "get", "network.wan.dns"); e == nil && v != "" {
		wan["dns"] = strings.Fields(v)
	}
	out["wan"] = wan
	_, e := run("/etc/init.d/nikki", "status")
	out["nikki"] = e == nil
	return out, nil
}
func cpuPercent() string {
	b, e := os.ReadFile("/proc/stat")
	if e != nil {
		return "—"
	}
	f := strings.Fields(strings.SplitN(string(b), "\n", 2)[0])
	if len(f) < 5 {
		return "—"
	}
	var v []uint64
	for _, x := range f[1:] {
		n, _ := strconv.ParseUint(x, 10, 64)
		v = append(v, n)
	}
	var total, idle uint64
	for i, n := range v {
		total += n
		if i == 3 || i == 4 {
			idle += n
		}
	}
	cpuMu.Lock()
	defer cpuMu.Unlock()
	now := time.Now()
	pct := 0.0
	if lastCPU.total > 0 && total > lastCPU.total {
		pct = 100 * float64((total-lastCPU.total)-(idle-lastCPU.idle)) / float64(total-lastCPU.total)
	}
	lastCPU.idle = idle
	lastCPU.total = total
	lastCPU.at = now
	if pct < 0 {
		pct = 0
	}
	if pct > 100 {
		pct = 100
	}
	return fmt.Sprintf("%.0f%%", pct)
}
func wanApply(w http.ResponseWriter, r *http.Request) {
	var x struct {
		Proto    string `json:"proto"`
		Username string `json:"username"`
		Password string `json:"password"`
		IPAddr   string `json:"ipaddr"`
		Netmask  string `json:"netmask"`
		Gateway  string `json:"gateway"`
		DNS      string `json:"dns"`
	}
	if bodyJSON(r, &x) != nil {
		fail(w, 400, "请求格式错误")
		return
	}
	if x.Proto != "dhcp" && x.Proto != "pppoe" && x.Proto != "static" {
		fail(w, 400, "不支持的 WAN 协议")
		return
	}
	if x.Proto == "pppoe" && (x.Username == "" || len(x.Username) > 128 || len(x.Password) > 256) {
		fail(w, 400, "PPPoE 账号不能为空，字段过长")
		return
	}
	if x.Proto == "static" {
		if net.ParseIP(x.IPAddr) == nil || net.ParseIP(x.Gateway) == nil || net.ParseIP(x.Netmask) == nil || strings.Contains(x.IPAddr, ":") {
			fail(w, 400, "静态 IPv4 地址、网关或子网掩码格式错误")
			return
		}
	}
	dns := []string{}
	if strings.TrimSpace(x.DNS) != "" {
		for _, v := range strings.Split(x.DNS, ",") {
			v = strings.TrimSpace(v)
			if net.ParseIP(v) == nil {
				fail(w, 400, "DNS 地址无效："+v)
				return
			}
			dns = append(dns, v)
		}
	}
	// Save the old network config, then launch an independent 120-second watchdog.
	backup, e := run("uci", "export", "network")
	if e != nil {
		fail(w, 500, "无法备份网络配置")
		return
	}
	if e = writeFile("/tmp/dualweb-network-backup", backup, 0600); e != nil {
		fail(w, 500, "无法写入网络备份")
		return
	}
	id := randomHex(8)
	_ = os.Remove("/tmp/dualweb-confirm")
	_ = writeFile("/tmp/dualweb-rollback-id", id, 0600)
	script := fmt.Sprintf("( sleep 120; [ -f /tmp/dualweb-confirm ] && [ \"$(cat /tmp/dualweb-confirm)\" = %q ] && exit 0; [ \"$(cat /tmp/dualweb-rollback-id 2>/dev/null)\" = %q ] || exit 0; uci import network < /tmp/dualweb-network-backup; uci commit network; /etc/init.d/network reload; rm -f /tmp/dualweb-rollback-id /tmp/dualweb-confirm ) >/tmp/dualweb-rollback.log 2>&1 &", id, id)
	if _, e = run("sh", "-c", script); e != nil {
		fail(w, 500, "无法启动回滚看门狗")
		return
	}
	set := func(k, v string) error { _, e := run("uci", "set", k+"="+v); return e }
	del := func(k string) { _, _ = run("uci", "-q", "delete", k) }
	if e = set("network.wan.proto", x.Proto); e != nil {
		fail(w, 500, "设置 WAN 协议失败")
		return
	}
	switch x.Proto {
	case "dhcp":
		del("network.wan.username")
		del("network.wan.password")
		del("network.wan.ipaddr")
		del("network.wan.netmask")
		del("network.wan.gateway")
	case "pppoe":
		if e = set("network.wan.username", x.Username); e == nil {
			e = set("network.wan.password", x.Password)
		}
		if e != nil {
			fail(w, 500, "设置 PPPoE 参数失败")
			return
		}
		del("network.wan.ipaddr")
		del("network.wan.netmask")
		del("network.wan.gateway")
	case "static":
		for k, v := range map[string]string{"ipaddr": x.IPAddr, "netmask": x.Netmask, "gateway": x.Gateway} {
			if e = set("network.wan."+k, v); e != nil {
				fail(w, 500, "设置静态 IP 失败")
				return
			}
		}
		del("network.wan.username")
		del("network.wan.password")
	}
	del("network.wan.dns")
	for _, d := range dns {
		if _, e = run("uci", "add_list", "network.wan.dns="+d); e != nil {
			fail(w, 500, "设置 DNS 失败")
			return
		}
	}
	if _, e = run("uci", "commit", "network"); e != nil {
		fail(w, 500, "提交 WAN 配置失败")
		return
	}
	if _, e = run("/etc/init.d/network", "reload"); e != nil {
		fail(w, 500, "网络重载失败，回滚看门狗仍会尝试恢复")
		return
	}
	writeJSON(w, 200, reply{"ok": true, "rollbackId": id, "timeout": 120})
}
func mihomoRequest(method, path string, body []byte) (*http.Response, error) {
	secret := readFile("/etc/dualweb/mihomo-secret")
	req, e := http.NewRequest(method, mihomoBase+path, bytes.NewReader(body))
	if e != nil {
		return nil, e
	}
	req.Header.Set("Authorization", "Bearer "+secret)
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	resp, e := httpClient.Do(req)
	if e != nil {
		return nil, errors.New("Mihomo 控制器不可用：请检查 Nikki 配置中的 external-controller 和 secret")
	}
	return resp, nil
}
func mihomoGroups(w http.ResponseWriter) {
	r, e := mihomoRequest(http.MethodGet, "/proxies", nil)
	if e != nil {
		fail(w, 502, e.Error())
		return
	}
	defer r.Body.Close()
	if r.StatusCode != 200 {
		fail(w, 502, "Mihomo API 返回 HTTP "+strconv.Itoa(r.StatusCode))
		return
	}
	var d struct {
		Proxies map[string]struct {
			Type string   `json:"type"`
			Now  string   `json:"now"`
			All  []string `json:"all"`
		} `json:"proxies"`
	}
	if json.NewDecoder(io.LimitReader(r.Body, 2<<20)).Decode(&d) != nil {
		fail(w, 502, "Mihomo 返回格式错误")
		return
	}
	groups := []reply{}
	for name, p := range d.Proxies {
		if p.Type == "Selector" || p.Type == "URLTest" || p.Type == "Fallback" || p.Type == "LoadBalance" {
			groups = append(groups, reply{"name": name, "now": p.Now, "type": p.Type})
		}
	}
	writeJSON(w, 200, reply{"groups": groups})
}
func mihomoGroup(w http.ResponseWriter, name string) {
	if !validLabel(name) {
		fail(w, 400, "策略组名称无效")
		return
	}
	r, e := mihomoRequest(http.MethodGet, "/proxies/"+url.PathEscape(name), nil)
	if e != nil {
		fail(w, 502, e.Error())
		return
	}
	defer r.Body.Close()
	if r.StatusCode != 200 {
		fail(w, 502, "Mihomo API 返回 HTTP "+strconv.Itoa(r.StatusCode))
		return
	}
	var d struct {
		Proxy struct {
			Now  string   `json:"now"`
			All  []string `json:"all"`
			Type string   `json:"type"`
		} `json:"proxy"`
	}
	if json.NewDecoder(io.LimitReader(r.Body, 1<<20)).Decode(&d) != nil {
		fail(w, 502, "Mihomo 返回格式错误")
		return
	}
	writeJSON(w, 200, reply{"now": d.Proxy.Now, "all": d.Proxy.All, "type": d.Proxy.Type})
}

type probeTarget struct { ID string `json:"id"`; Name string `json:"name"`; URL string `json:"url"` }
type probeResult struct { ID string `json:"id"`; Name string `json:"name"`; OK bool `json:"ok"`; LatencyMS int64 `json:"latencyMs"`; TargetIP string `json:"targetIP,omitempty"`; Status string `json:"status,omitempty"`; Error string `json:"error,omitempty"` }
func probeOne(t probeTarget) probeResult {
	result := probeResult{ID:t.ID, Name:t.Name}
	u, err := url.Parse(t.URL); if err != nil { result.Error = "检测地址无效"; return result }
	start := time.Now(); var ipMu sync.Mutex; connectedIP := ""
	transport := &http.Transport{Proxy:nil, DialContext:func(ctx context.Context, network, address string)(net.Conn,error){
		conn,e:=(&net.Dialer{Timeout:4*time.Second,KeepAlive:15*time.Second}).DialContext(ctx,network,address)
		if e==nil { host,_,splitErr:=net.SplitHostPort(conn.RemoteAddr().String()); if splitErr==nil { ipMu.Lock(); connectedIP=host; ipMu.Unlock() } }; return conn,e
	},TLSHandshakeTimeout:4*time.Second,ResponseHeaderTimeout:4*time.Second,DisableKeepAlives:true}
	client:=&http.Client{Transport:transport,Timeout:7*time.Second,CheckRedirect:func(req *http.Request,via []*http.Request)error{if len(via)>=3{return http.ErrUseLastResponse};return nil}}
	defer transport.CloseIdleConnections()
	req,err:=http.NewRequest(http.MethodGet,t.URL,nil); if err!=nil {result.Error=err.Error();return result}
	req.Header.Set("User-Agent","DualWeb-Connectivity/1.0"); req.Header.Set("Range","bytes=0-0")
	resp,err:=client.Do(req); result.LatencyMS=time.Since(start).Milliseconds()
	ipMu.Lock(); result.TargetIP=connectedIP; ipMu.Unlock()
	if result.TargetIP=="" {ips,_:=net.LookupIP(u.Hostname());if len(ips)>0{result.TargetIP=ips[0].String()}}
	if err!=nil {result.Error="连接失败："+err.Error();return result}
	defer resp.Body.Close(); result.Status=resp.Status; _,_=io.Copy(io.Discard,io.LimitReader(resp.Body,1024))
	result.OK=resp.StatusCode>=200&&resp.StatusCode<500; if !result.OK {result.Error="HTTP 返回异常状态"}; return result
}
func connectivity(w http.ResponseWriter) {
	targets:=[]probeTarget{{ID:"aliyun",Name:"阿里云",URL:"https://www.aliyun.com/"},{ID:"google",Name:"Google",URL:"https://www.google.com/generate_204"},{ID:"github",Name:"GitHub",URL:"https://github.com/"},{ID:"telegram",Name:"Telegram",URL:"https://telegram.org/"}}
	results:=make([]probeResult,len(targets));var wg sync.WaitGroup
	for i,t:=range targets {wg.Add(1);go func(i int,t probeTarget){defer wg.Done();results[i]=probeOne(t)}(i,t)}
	wg.Wait();writeJSON(w,200,reply{"results":results,"checkedAt":time.Now().Format("2006-01-02 15:04:05")})
}

func main() {
	_ = os.MkdirAll("/etc/dualweb", 0700)
	mux := http.NewServeMux()
	mux.HandleFunc("/api/", route)
	srv := &http.Server{Addr: listenAddr, Handler: mux, ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 10 * time.Second, WriteTimeout: 20 * time.Second, IdleTimeout: 60 * time.Second}
	if e := srv.ListenAndServe(); e != nil {
		fmt.Fprintln(os.Stderr, e)
		os.Exit(1)
	}
}
