#!/bin/bash
# Mock PG (PortOne 스타일) EC2 초기화
# Terraform templatefile()로 렌더링됨
set -euo pipefail
exec > /var/log/user-data.log 2>&1

echo "[init] Mock PG EC2 초기화 시작: $(date)"

# ── Node.js 설치 (Amazon Linux 2023 기본 Node 18 이상) ────────
dnf update -y
dnf install -y nodejs npm

echo "[init] Node.js 버전: $(node --version)"

# ── 앱 디렉토리 ────────────────────────────────────────────────
mkdir -p /opt/mockpg
cd /opt/mockpg

# ── package.json 생성 ──────────────────────────────────────────
cat > /opt/mockpg/package.json << 'PKGEOF'
{
  "name": "mock-pg",
  "version": "1.0.0",
  "description": "PortOne style Mock PG server",
  "main": "server.js",
  "dependencies": {
    "express": "^4.18.0"
  }
}
PKGEOF

# ── S3에서 server.js 다운로드 ─────────────────────────────────
S3_BUCKET="${s3_bucket}"
echo "[init] S3에서 server.js 다운로드"
aws s3 cp "s3://$S3_BUCKET/scripts/server.js" /opt/mockpg/server.js --region ap-northeast-2

# ── npm install ────────────────────────────────────────────────
cd /opt/mockpg
npm install --production
chown -R ec2-user:ec2-user /opt/mockpg

echo "[init] npm 패키지 설치 완료"

# ── systemd 서비스 ─────────────────────────────────────────────
cat > /etc/systemd/system/mockpg.service << 'SVCEOF'
[Unit]
Description=Mock PG Server (PortOne style)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/opt/mockpg
ExecStart=/usr/bin/node /opt/mockpg/server.js
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable mockpg
systemctl start mockpg

echo "[init] Mock PG 서비스 시작 완료: $(date)"

# ── 시나리오 변경 헬퍼 (SSM에서 호출 가능) ────────────────────
cat > /opt/mockpg/set-scenario.sh << 'SCNEOF'
#!/bin/bash
# 사용: bash /opt/mockpg/set-scenario.sh [optimistic|realistic|peak|worst]
SCENARIO=$${1:-realistic}
curl -s -X PUT http://localhost:3000/scenario \
  -H 'Content-Type: application/json' \
  -d "{\"scenario\": \"$$SCENARIO\"}" | python3 -m json.tool
SCNEOF
chmod +x /opt/mockpg/set-scenario.sh

echo "[init] 완료: $(date)"
