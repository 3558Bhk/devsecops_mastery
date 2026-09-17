# Networking Fundamentals - SDE3

## OSI Model (7 Layers) vs TCP/IP (4 Layers)

| OSI | TCP/IP | Example | SDE3 Relevance |
|-----|--------|---------|----------------|
| 7 Application | Application | HTTP, DNS, FTP | API, browser |
| 6 Presentation | | SSL/TLS, JSON | Encryption, serialization |
| 5 Session | | NetBIOS | Sessions |
| 4 Transport | Transport | TCP, UDP | Ports, reliability |
| 3 Network | Internet | IP, ICMP | Routing, IP |
| 2 Data Link | Link | MAC, ARP | Switch |
| 1 Physical | | Cables | |

**Interview: What happens when you type google.com?**
1. Browser checks cache -> OS cache -> Router cache -> ISP DNS -> Root -> TLD -> Authoritative DNS
2. DNS returns IP (e.g. 142.250.195.14)
3. Browser opens TCP connection (3-way handshake)
4. TLS handshake if HTTPS
5. HTTP request GET /
6. Server responds
7. Browser renders HTML, fetches assets

## TCP vs UDP

| TCP | UDP |
|-----|-----|
| Connection oriented (3-way handshake) | Connectionless |
| Reliable, ordered, retransmission | Unreliable, no order |
| Slow (ack overhead) | Fast |
| Use: HTTP, SMTP, DB | Use: DNS, video streaming, VoIP, gaming, DHCP |
| Header 20 bytes | Header 8 bytes |

### TCP 3-Way Handshake
1. SYN: Client -> Server (Seq=x)
2. SYN-ACK: Server -> Client (Seq=y, Ack=x+1)
3. ACK: Client -> Server (Seq=x+1, Ack=y+1)
- Then data transfer
- 4-way termination: FIN, ACK, FIN, ACK

### TCP Flow Control
- Sliding window, congestion control (slow start, congestion avoidance)

## IP
- IPv4: 32-bit, 4.3B addresses, e.g. 192.168.1.1, NAT needed
- IPv6: 128-bit, huge, e.g. 2001:0db8::1
- Public vs Private: Private 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16
- Subnet: /24 = 255.255.255.0 = 256 IPs

## DNS
- Port 53 UDP/TCP
- Records:
  - A: IPv4
  - AAAA: IPv6
  - CNAME: Alias
  - MX: Mail
  - TXT: Verification
  - NS: Name server
  - SRV: Service
- TTL: Time to live cache
- Tools: dig, nslookup

## HTTP Versions
- **HTTP/1.1**: Text, 1 request per TCP connection (keep-alive reuse), head-of-line blocking
- **HTTP/2**: Binary, multiplexing (many streams one TCP), header compression (HPACK), server push
- **HTTP/3**: QUIC over UDP, 0-RTT, no head-of-line blocking at transport, better mobile

## Load Balancing Algorithms
- Round Robin
- Weighted Round Robin
- Least Connections
- Least Response Time
- IP Hash (sticky)
- Consistent Hashing

## NAT & Firewall
- NAT: Private to public IP translation
- Firewall: Rules allow/deny IP:port

## VPC Basics
- Virtual Private Cloud: Isolated network in cloud
- Subnet: Public (IGW) vs Private (NAT Gateway)
- Security Group: Instance level stateful firewall
- NACL: Subnet level stateless
- Route Table

## Common Commands Recap
```bash
ping -c 4 google.com # ICMP
traceroute google.com # path
dig google.com +short
nslookup google.com
curl -I https://google.com
telnet google.com 443 # check port open
nc -zv google.com 443 # netcat
```
