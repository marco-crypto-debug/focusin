#!/usr/bin/env python3
"""
FocusIn Multicast Probe — 測量教室 AP 的 UDP 組播實際吞吐
===========================================================
用法（在兩台 Mac 上）:

  # 學生機（接收端）先啟動，例如收 60 秒:
  python3 multicast_probe.py recv --duration 60

  # 教師機（發送端）固定速率測試，例如 4 Mbps:
  python3 multicast_probe.py send --rate 4

  # 教師機階梯測試: 從 2 Mbps 開始，每 8 秒升 2 Mbps，到 12 Mbps 停:
  python3 multicast_probe.py send --rate 2 --max-rate 12 --step 2 --stage 8

接收端會每 5 秒輸出一個統計窗口（收到速率 / 丟包率 / 延遲），
對照發送端的階梯時序即可看出 AP 在多少 Mbps 開始丟包。

預設組播組: 239.255.42.99:7000（可透過 --group / --port 修改）
同一子網的 AP 若不支援 multicast 或開了 client isolation，接收端會收到 0 包。
"""

import argparse
import socket
import struct
import sys
import time

MAGIC = b"FZMP"          # 4B 魔數
HEADER_SIZE = 16         # magic(4) + seq(4) + timestamp(8)
DEFAULT_GROUP = "239.255.42.99"
DEFAULT_PORT = 7000
DEFAULT_PAYLOAD = 1456   # 1456 + 16 = 1472 = 乙太網 MTU 1500 - IP20 - UDP8


def resolve_iface_ip():
    """找出預設路由介面的本機 IP（用於加入組播組）。"""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            s.settimeout(0.5)
            s.connect(("8.8.8.8", 80))  # 只觸發路由，不實際發包
            return s.getsockname()[0]
        finally:
            s.close()
    except OSError:
        # 離線/無預設路由時：從路由表找第一個非 loopback 介面
        try:
            import subprocess
            out = subprocess.run(["route", "-n", "get", "default"],
                                 capture_output=True, text=True, timeout=2).stdout
            for line in out.splitlines():
                if "interface:" in line:
                    iface = line.split(":")[1].strip()
                    ip = subprocess.run(["ipconfig", "getifaddr", iface],
                                        capture_output=True, text=True, timeout=2).stdout.strip()
                    if ip:
                        return ip
        except Exception:
            pass
        return "0.0.0.0"


def make_sender_socket(iface_ip):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    s.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 1)
    s.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_IF,
                 socket.inet_aton(iface_ip))
    return s


def make_receiver_socket(group, port, iface_ip):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("", port))
    # macOS: IP_ADD_MEMBERSHIP 需要 ip_mreq = group(4B) + interface(4B)
    mreq = socket.inet_aton(group) + socket.inet_aton(iface_ip)
    s.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)
    s.settimeout(1.0)
    return s


def cmd_send(args):
    group = args.group
    port = args.port
    iface_ip = args.iface if args.iface else resolve_iface_ip()
    payload_size = args.payload
    packet_total = HEADER_SIZE + payload_size
    rate_mbps = args.rate
    max_rate = args.max_rate or args.rate
    step = args.step or 0
    stage = args.stage or 10

    sock = make_sender_socket(iface_ip)
    addr = (group, port)

    print(f"🔹 發送端  {group}:{port}  介面 {iface_ip}  包大小 {packet_total}B")
    print(f"🔹 階梯: {rate_mbps} Mbps → {max_rate} Mbps (每 {stage}s 升 {step} Mbps)\n")
    print("請先在學生機啟動:  python3 multicast_probe.py recv\n")

    current_rate = rate_mbps
    stage_start = time.time()
    start = time.time()
    seq = 0
    payload = bytes(payload_size)

    try:
        while current_rate <= max_rate:
            bytes_per_sec = current_rate * 1_000_000 / 8
            interval = packet_total / bytes_per_sec  # 秒/包
            stage_elapsed = time.time() - stage_start

            if args.seconds is not None and time.time() - start >= args.seconds:
                break
            if stage_elapsed >= stage:
                if args.max_rate is None:
                    # 固定速率模式：不升檔，重置計時繼續跑
                    stage_start = time.time()
                    continue
                current_rate += step
                stage_start = time.time()
                if current_rate <= max_rate:
                    print(f"\n--- 升檔: {current_rate} Mbps ({time.strftime('%H:%M:%S')}) ---\n")
                continue

            header = MAGIC + struct.pack(">I", seq) + struct.pack(">d", time.time())
            sock.sendto(header + payload, addr)
            seq += 1
            time.sleep(max(interval - (time.time() - stage_start - stage_elapsed), 0))
    except KeyboardInterrupt:
        pass
    finally:
        elapsed = time.time() - start
        mbps = (seq * packet_total * 8) / 1_000_000 / elapsed
        print(f"\n✔ 結束: {seq} 包 / {elapsed:.1f}s / 平均 {mbps:.1f} Mbps")
        sock.close()


def cmd_recv(args):
    group = args.group
    port = args.port
    iface_ip = args.iface if args.iface else resolve_iface_ip()
    duration = args.duration
    window = 5  # 每 5 秒輸出一個統計窗口

    sock = make_receiver_socket(group, port, iface_ip)
    print(f"🔹 接收端  {group}:{port}  介面 {iface_ip}  監聽 {duration}s")
    print(f"🔹 每 {window}s 輸出: 收包數 / 速率 / 丟包率\n")

    last_seq = None
    seq_gaps = 0
    total_packets = 0
    total_bytes = 0
    window_start = time.time()
    start = time.time()
    samples = 0
    grand_packets = 0
    grand_bytes = 0

    def flush_window(reason="時間窗"):
        nonlocal last_seq, seq_gaps, total_packets, total_bytes, window_start, samples, grand_packets, grand_bytes
        elapsed = time.time() - window_start
        if elapsed <= 0 or samples == 0:
            window_start = time.time()
            return
        mbps = (total_bytes * 8) / 1_000_000 / elapsed
        loss = seq_gaps / max(total_packets + seq_gaps, 1) * 100
        print(f"  [{time.strftime('%H:%M:%S')}] {total_packets:>7} 包  "
              f"{mbps:>6.2f} Mbps  {loss:>5.1f}% 丟包  ({reason})")
        grand_packets += total_packets
        grand_bytes += total_bytes
        last_seq = None
        seq_gaps = 0
        total_packets = 0
        total_bytes = 0
        window_start = time.time()
        samples = 0

    try:
        while time.time() - start < duration:
            try:
                data, _ = sock.recvfrom(65535)
            except socket.timeout:
                continue
            if len(data) < HEADER_SIZE or data[:4] != MAGIC:
                continue
            seq = struct.unpack(">I", data[4:8])[0]
            ts = struct.unpack(">d", data[8:16])[0]
            if last_seq is not None:
                gap = seq - last_seq - 1
                if gap > 0:
                    seq_gaps += gap
            last_seq = seq
            total_packets += 1
            total_bytes += len(data)
            samples += 1
            if time.time() - window_start >= window:
                flush_window()
        flush_window("結束")
        elapsed = time.time() - start
        if grand_packets > 0:
            print(f"\n✔ 總計: {grand_packets} 包 / {elapsed:.0f}s "
                  f"/ 平均 {(grand_bytes * 8) / 1_000_000 / elapsed:.2f} Mbps")
        else:
            print("\n⚠ 未收到任何組播包")
            print("  可能原因: AP 不支援 multicast / client isolation / 不同子網 / 發送端未啟動")
    except KeyboardInterrupt:
        flush_window("中斷")


def main():
    parser = argparse.ArgumentParser(
        description="FocusIn Multicast Probe — 測 AP 組播吞吐")
    sub = parser.add_subparsers(dest="mode", required=True)

    for name in ("send", "recv"):
        p = sub.add_parser(name)
        p.add_argument("--group", default=DEFAULT_GROUP)
        p.add_argument("--port", type=int, default=DEFAULT_PORT)
        p.add_argument("--iface", default="",
                       help="本機介面 IP（預設自動偵測預設路由介面）")
    p_send = sub.choices["send"]
    p_send.add_argument("--rate", type=float, default=4.0,
                        help="起始/固定速率 Mbps（預設 4）")
    p_send.add_argument("--max-rate", type=float, default=None,
                        help="階梯測試上限（預設同 --rate = 固定速率）")
    p_send.add_argument("--step", type=float, default=2.0,
                        help="每檔升多少 Mbps（預設 2）")
    p_send.add_argument("--stage", type=float, default=8.0,
                        help="每檔持續秒數（預設 8）")
    p_send.add_argument("--payload", type=int, default=DEFAULT_PAYLOAD,
                        help="payload 大小（預設 1456，整包 1472）")
    p_send.add_argument("--seconds", type=float, default=None,
                        help="發送秒數（預設無限，Ctrl+C 停止）")
    p_recv = sub.choices["recv"]
    p_recv.add_argument("--duration", type=int, default=60,
                        help="監聽秒數（預設 60）")

    args = parser.parse_args()
    if args.mode == "send":
        cmd_send(args)
    else:
        cmd_recv(args)


if __name__ == "__main__":
    main()
