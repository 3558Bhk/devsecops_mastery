# Linux Commands - SDE3 Must Know

## File System
```bash
ls -lah
pwd
cd /var/log
mkdir -p a/b/c
touch file.txt
cp -r src dest
mv file newfile
rm -rf folder # careful
find . -name "*.log" -type f
find . -size +100M
grep -r "ERROR" /var/log/
grep -i -n "exception" app.log
cat file | grep error
tail -f app.log
tail -n 100 app.log
head -n 50 file
less app.log # q to exit
wc -l file
du -sh * | sort -hr
df -h
```

## Process Management
```bash
ps aux | grep java
ps -ef
top
htop
kill -9 PID
killall -9 node
jobs
bg / fg
nohup java -jar app.jar &
```

## System Info
```bash
uname -a
lscpu
free -h
uptime
whoami
id
env
echo $PATH
```

## Networking
```bash
ping google.com
curl -v http://localhost:8080/health
curl -X POST -H "Content-Type: application/json" -d '{"key":"val"}' http://api/test
wget https://example.com/file.zip
ifconfig / ip addr
netstat -tulpn
ss -tulpn
nslookup google.com
dig google.com
traceroute google.com
ssh user@host -p 22
scp file.txt user@host:/tmp/
rsync -avz src/ dest/
```

## Permissions
```bash
chmod 755 file
chmod +x script.sh
chown user:group file
ls -l
sudo su -
```

## Archiving & Package
```bash
tar -czvf archive.tar.gz folder/
tar -xzvf archive.tar.gz
zip -r file.zip folder/
unzip file.zip
apt update && apt install nginx -y
yum install nginx -y
```

## One Liners for Interview
```bash
# Find top 10 large files
find / -type f -size +100M -exec ls -lh {} \; 2>/dev/null | awk '{print $9 ": " $5}' | sort -hr | head -10

# Count 500 errors in log
grep " 500 " access.log | wc -l

# Check memory hog
ps aux --sort=-%mem | head -10

# Replace text in files
sed -i 's/old/new/g' file.txt
awk '{print $1}' file.txt | sort | uniq -c | sort -nr
```
