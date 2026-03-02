#!/bin/bash
# Spring Boot EC2 초기화 스크립트
# Terraform templatefile()로 렌더링됨 - $${var}는 Terraform 변수
set -euo pipefail
exec > /var/log/user-data.log 2>&1

echo "[init] Spring Boot EC2 초기화 시작: $(date)"

# ── 패키지 설치 ──────────────────────────────────────────────
dnf update -y
dnf install -y java-17-amazon-corretto

echo "[init] Java 17 설치 완료"

# ── 앱 디렉토리 생성 ──────────────────────────────────────────
mkdir -p /opt/timedeal
chown -R ec2-user:ec2-user /opt/timedeal

# ── 환경 변수 파일 (600 권한, DB 비밀번호 보호) ───────────────
cat > /opt/timedeal/.env << 'ENVEOF'
SPRING_PROFILES_ACTIVE=prod
DB_HOST=${db_host}
DB_NAME=${db_name}
DB_USER=${db_username}
DB_PASSWORD=${db_password}
REDIS_HOST=${redis_host}
PG_URL=http://${mockpg_host}:3000
AWS_REGION=ap-northeast-2
ENVEOF
chmod 600 /opt/timedeal/.env
chown ec2-user:ec2-user /opt/timedeal/.env

echo "[init] 환경변수 파일 생성 완료"

# ── systemd 서비스 ────────────────────────────────────────────
cat > /etc/systemd/system/timedeal.service << 'SVCEOF'
[Unit]
Description=Timedeal Spring Boot Application
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/opt/timedeal
EnvironmentFile=/opt/timedeal/.env
ExecStartPre=/bin/bash -c 'for i in $(seq 1 60); do [ -f /opt/timedeal/app.jar ] && exit 0; echo "JAR 대기중... ($i/60)"; sleep 5; done; exit 1'
ExecStart=/usr/bin/java -Xms512m -Xmx1500m -jar /opt/timedeal/app.jar
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable timedeal

echo "[init] systemd 서비스 등록 완료"

# ── 배포 스크립트 (SSM에서 호출: sudo /opt/timedeal/deploy.sh) ─
cat > /opt/timedeal/deploy.sh << 'DEPLOYEOF'
#!/bin/bash
set -euo pipefail
S3_BUCKET="${s3_bucket}"
echo "[deploy] S3에서 JAR 다운로드: s3://$S3_BUCKET/artifacts/app.jar"
aws s3 cp "s3://$S3_BUCKET/artifacts/app.jar" /opt/timedeal/app.jar --region ap-northeast-2
chown ec2-user:ec2-user /opt/timedeal/app.jar
echo "[deploy] 서비스 재시작..."
systemctl restart timedeal
sleep 5
systemctl status timedeal --no-pager
echo "[deploy] 완료"
DEPLOYEOF
chmod +x /opt/timedeal/deploy.sh
chown ec2-user:ec2-user /opt/timedeal/deploy.sh

# ── S3에서 JAR 자동 다운로드 시도 ─────────────────────────────
S3_BUCKET="${s3_bucket}"
echo "[init] S3에서 JAR 확인: s3://$S3_BUCKET/artifacts/app.jar"
if aws s3 ls "s3://$S3_BUCKET/artifacts/app.jar" --region ap-northeast-2 2>/dev/null; then
    echo "[init] JAR 발견 - 다운로드 중..."
    aws s3 cp "s3://$S3_BUCKET/artifacts/app.jar" /opt/timedeal/app.jar --region ap-northeast-2
    chown ec2-user:ec2-user /opt/timedeal/app.jar
    systemctl start timedeal
    echo "[init] 서비스 시작 완료"
else
    echo "[init] JAR 없음 - 서비스는 JAR 배포 후 자동 시작됩니다"
    echo "[init] 배포 명령: aws s3 cp target/*.jar s3://$S3_BUCKET/artifacts/app.jar && sudo /opt/timedeal/deploy.sh"
    systemctl start timedeal  # JAR 대기 상태로 시작 (ExecStartPre에서 60초 대기)
fi

echo "[init] 완료: $(date)"
