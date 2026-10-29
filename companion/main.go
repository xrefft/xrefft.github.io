// Cloudflare 优选助手：仅在本机运行，保持证书校验并直连候选 IP。
package main

import (
	"context"
	"crypto/rand"
	"crypto/tls"
	"embed"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"io/fs"
	"log"
	"net"
	"net/http"
	"net/netip"
	"os"
	"os/exec"
	"runtime"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

//go:embed web/*
var assets embed.FS

var version = "dev"

const address = "127.0.0.1:38479"
const origin = "http://" + address
const testHost = "speed.cloudflare.com"

var cloudflareRanges = func() []netip.Prefix {
	ranges := []string{"173.245.48.0/20", "103.21.244.0/22", "103.22.200.0/22", "103.31.4.0/22", "141.101.64.0/18", "108.162.192.0/18", "190.93.240.0/20", "188.114.96.0/20", "197.234.240.0/22", "198.41.128.0/17", "162.158.0.0/15", "104.16.0.0/13", "104.24.0.0/14", "172.64.0.0/13", "131.0.72.0/22"}
	result := make([]netip.Prefix, 0, len(ranges))
	for _, s := range ranges {
		result = append(result, netip.MustParsePrefix(s))
	}
	return result
}()

type testRequest struct {
	IPs           []string `json:"ips"`
	Host          string   `json:"host"`
	Samples       int      `json:"samples"`
	DownloadBytes int64    `json:"downloadBytes"`
}
type result struct {
	IP           string   `json:"ip"`
	Successes    int      `json:"successes"`
	Attempts     int      `json:"attempts"`
	FailureRate  float64  `json:"failureRate"`
	LatencyMS    *float64 `json:"latencyMs"`
	DownloadMbps *float64 `json:"downloadMbps"`
	Bytes        int64    `json:"bytes"`
	Errors       []string `json:"errors"`
}
type server struct {
	token string
	busy  atomic.Bool
	files http.Handler
}

func main() {
	open := flag.Bool("open", false, "启动后打开本地测速网页")
	showVersion := flag.Bool("version", false, "显示版本")
	flag.Parse()
	for _, argument := range flag.Args() {
		if argument != "cfspeed://open" {
			fmt.Fprintln(os.Stderr, "不接受此启动参数：", argument)
			os.Exit(2)
		}
	}
	if *showVersion {
		fmt.Println(version)
		return
	}
	s, err := newServer()
	if err != nil {
		log.Fatal(err)
	}
	listener, err := net.Listen("tcp4", address)
	if err != nil {
		if *open && existingCompanion() {
			if openErr := openBrowser(origin); openErr != nil {
				log.Printf("请手动打开 %s：%v", origin, openErr)
			}
			return
		}
		log.Fatalf("无法监听 %s，且未确认该端口为 Cloudflare 优选助手；请检查端口占用（%v）", address, err)
	}
	httpServer := &http.Server{Handler: s, ReadHeaderTimeout: 5 * time.Second, IdleTimeout: 30 * time.Second, MaxHeaderBytes: 16 << 10}
	fmt.Printf("Cloudflare 优选助手 %s\n请在浏览器打开 %s\n按 Ctrl+C 退出。\n", version, origin)
	if *open {
		go func() {
			if err := openBrowser(origin); err != nil {
				log.Printf("无法自动打开浏览器，请手动打开上述地址：%v", err)
			}
		}()
	}
	log.Fatal(httpServer.Serve(listener))
}
func existingCompanion() bool {
	client := &http.Client{Timeout: 2 * time.Second, Transport: &http.Transport{Proxy: nil}, CheckRedirect: func(*http.Request, []*http.Request) error { return errors.New("不接受重定向") }}
	response, err := client.Get(origin + "/api/info")
	if err != nil {
		return false
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return false
	}
	var identity struct {
		App string `json:"app"`
	}
	if json.NewDecoder(io.LimitReader(response.Body, 4096)).Decode(&identity) != nil {
		return false
	}
	return identity.App == "cf-speed"
}
func openBrowser(url string) error {
	var cmd *exec.Cmd
	switch runtime.GOOS {
	case "windows":
		cmd = exec.Command("rundll32", "url.dll,FileProtocolHandler", url)
	case "darwin":
		cmd = exec.Command("open", url)
	default:
		cmd = exec.Command("xdg-open", url)
	}
	return cmd.Run()
}
func newServer() (*server, error) {
	token := make([]byte, 32)
	if _, err := rand.Read(token); err != nil {
		return nil, err
	}
	web, err := fs.Sub(assets, "web")
	if err != nil {
		return nil, err
	}
	return &server{token: hex.EncodeToString(token), files: http.FileServer(http.FS(web))}, nil
}
func jsonResponse(w http.ResponseWriter, status int, data any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(data)
}
func reject(w http.ResponseWriter, status int, message string) {
	jsonResponse(w, status, map[string]string{"error": message})
}
func (s *server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set("Content-Security-Policy", "default-src 'self'; connect-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; frame-ancestors 'none'; base-uri 'none'")
	if r.Host != address {
		reject(w, http.StatusForbidden, "只接受本机地址")
		return
	}
	if o := r.Header.Get("Origin"); o != "" && o != origin {
		reject(w, http.StatusForbidden, "请求来源不受信任")
		return
	}
	switch r.URL.Path {
	case "/api/info":
		if r.Method != http.MethodGet {
			reject(w, 405, "仅支持 GET")
			return
		}
		jsonResponse(w, 200, map[string]string{"version": version, "token": s.token, "app": "cf-speed"})
	case "/api/test":
		s.handleTest(w, r)
	default:
		if strings.HasPrefix(r.URL.Path, "/api/") {
			reject(w, 404, "接口不存在")
			return
		}
		if r.Method != http.MethodGet && r.Method != http.MethodHead {
			reject(w, 405, "仅支持 GET")
			return
		}
		s.files.ServeHTTP(w, r)
	}
}
func (s *server) handleTest(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		reject(w, 405, "仅支持 POST")
		return
	}
	if r.Header.Get("Origin") != origin || r.Header.Get("X-Session-Token") != s.token {
		reject(w, 403, "请从本地网页启动测速")
		return
	}
	if strings.TrimSpace(strings.Split(r.Header.Get("Content-Type"), ";")[0]) != "application/json" {
		reject(w, 415, "需要 application/json")
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, 64<<10)
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	var input testRequest
	if err := decoder.Decode(&input); err != nil {
		reject(w, 400, "请求 JSON 无效或超过 64KiB")
		return
	}
	if err := decoder.Decode(&struct{}{}); err != io.EOF {
		reject(w, 400, "只接受一个 JSON 对象")
		return
	}
	if err := validate(&input); err != nil {
		reject(w, 400, err.Error())
		return
	}
	if !s.busy.CompareAndSwap(false, true) {
		reject(w, 409, "已有测速运行，请先等待完成或取消")
		return
	}
	defer s.busy.Store(false)
	results := runTests(r.Context(), input)
	if r.Context().Err() != nil {
		return
	}
	jsonResponse(w, 200, map[string]any{"results": results})
}
func validate(input *testRequest) error {
	if input.Host != testHost {
		return errors.New("host 只能为 speed.cloudflare.com")
	}
	if input.Samples < 1 || input.Samples > 5 {
		return errors.New("samples 必须在 1–5 之间")
	}
	if input.DownloadBytes != 0 && input.DownloadBytes != 1000000 && input.DownloadBytes != 5000000 {
		return errors.New("downloadBytes 只能为 0、1000000、5000000")
	}
	if len(input.IPs) == 0 || len(input.IPs) > 64 {
		return errors.New("每次必须提供 1–64 个 IP")
	}
	seen := make(map[string]bool)
	for _, ip := range input.IPs {
		addr, err := netip.ParseAddr(ip)
		if err != nil || !addr.Is4() || seen[ip] {
			return fmt.Errorf("IP 无效或重复：%s", ip)
		}
		allowed := false
		for _, prefix := range cloudflareRanges {
			if prefix.Contains(addr) {
				allowed = true
				break
			}
		}
		if !allowed {
			return fmt.Errorf("IP 不在 Cloudflare 官方 IPv4 网段：%s", ip)
		}
		seen[ip] = true
	}
	return nil
}
func runTests(ctx context.Context, input testRequest) []result {
	results := make([]result, len(input.IPs))
	jobs := make(chan int)
	var workers sync.WaitGroup
	for worker := 0; worker < 4; worker++ {
		workers.Add(1)
		go func() {
			defer workers.Done()
			for index := range jobs {
				results[index] = testIP(ctx, input.IPs[index], input)
			}
		}()
	}
	for i := range input.IPs {
		select {
		case jobs <- i:
		case <-ctx.Done():
			close(jobs)
			workers.Wait()
			return nil
		}
	}
	close(jobs)
	workers.Wait()
	sort.SliceStable(results, func(i, j int) bool {
		a, b := results[i], results[j]
		if a.FailureRate != b.FailureRate {
			return a.FailureRate < b.FailureRate
		}
		if a.LatencyMS == nil {
			return false
		}
		if b.LatencyMS == nil {
			return true
		}
		return *a.LatencyMS < *b.LatencyMS
	})
	return results
}
func testIP(ctx context.Context, ip string, input testRequest) result {
	result := result{IP: ip, Errors: []string{}}
	var totalMS float64
	for sample := 0; sample < input.Samples; sample++ {
		if ctx.Err() != nil {
			return result
		}
		result.Attempts++
		elapsed, _, err := request(ctx, ip, 0)
		if err != nil {
			result.Errors = append(result.Errors, fmt.Sprintf("HTTPS 样本 %d：%v", sample+1, err))
			continue
		}
		result.Successes++
		totalMS += float64(elapsed) / float64(time.Millisecond)
	}
	if result.Successes > 0 {
		average := totalMS / float64(result.Successes)
		result.LatencyMS = &average
	}
	if input.DownloadBytes > 0 && ctx.Err() == nil {
		result.Attempts++
		elapsed, bytes, err := request(ctx, ip, input.DownloadBytes)
		result.Bytes = bytes
		if err != nil {
			result.Errors = append(result.Errors, fmt.Sprintf("下载：%v", err))
		} else {
			result.Successes++
			speed := float64(bytes) * 8 / elapsed.Seconds() / 1000000
			result.DownloadMbps = &speed
		}
	}
	if result.Attempts > 0 {
		result.FailureRate = float64(result.Attempts-result.Successes) / float64(result.Attempts)
	}
	return result
}

// 每次建立新的 TCP/TLS 连接；DNS 不参与候选 IP 的选择，TLS 仍验证测速域名。
func request(ctx context.Context, ip string, bytes int64) (time.Duration, int64, error) {
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	transport := &http.Transport{
		Proxy: nil,
		DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
			return (&net.Dialer{}).DialContext(ctx, "tcp4", net.JoinHostPort(ip, "443"))
		},
		TLSClientConfig:       &tls.Config{ServerName: testHost, MinVersion: tls.VersionTLS12},
		DisableKeepAlives:     true,
		DisableCompression:    true,
		ResponseHeaderTimeout: 5 * time.Second,
	}
	defer transport.CloseIdleConnections()
	client := &http.Client{Transport: transport, CheckRedirect: func(*http.Request, []*http.Request) error { return errors.New("不接受测速重定向") }}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, fmt.Sprintf("https://%s/__down?bytes=%d", testHost, bytes), nil)
	if err != nil {
		return 0, 0, err
	}
	req.Header.Set("Cache-Control", "no-cache")
	start := time.Now()
	response, err := client.Do(req)
	if err != nil {
		return time.Since(start), 0, err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return time.Since(start), 0, fmt.Errorf("HTTP %d", response.StatusCode)
	}
	// 多读一个字节识别超量响应，防止不限量下载。
	count, err := io.Copy(io.Discard, io.LimitReader(response.Body, bytes+1))
	elapsed := time.Since(start)
	if err != nil {
		return elapsed, count, err
	}
	if count != bytes {
		return elapsed, count, fmt.Errorf("响应字节数不符：实际 %d，预期 %d", count, bytes)
	}
	return elapsed, count, nil
}
