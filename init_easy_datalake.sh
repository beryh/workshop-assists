#!/bin/bash
echo "스크립트 시작: $(date)"

# 변수 설정
DB_NAME='ecommerce'
DB_USER='testuser'
DB_PASS='testuser'
ROOT_PASS='Root!@#123'
# Root 권한 확인
if [ "$EUID" -ne 0 ]; then
        echo "이 스크립트는 root 권한으로 실행해야 합니다."
        exit 1
fi

echo "MySQL 설치 준비 중..."
# 기존 MySQL 관련 파일 완전 제거
dnf remove -y mysql* mariadb*
rm -rf /var/lib/mysql
rm -rf /var/log/mysqld.log
rm -rf /etc/my.cnf
rm -rf /etc/my.cnf.d
rm -rf /var/log/mysql
rm -f /etc/yum.repos.d/mysql-community*
rm -f /etc/pki/rpm-gpg/RPM-GPG-KEY-mysql*
# dnf 캐시 정리
dnf clean all
# 필요한 디렉토리 생성
mkdir -p /etc/my.cnf.dmkdir -p /var/log/mysql

echo "MySQL Repository 설정 중..."
# MySQL Repository 설정 파일 직접 생성
cat > /etc/yum.repos.d/mysql-community.repo << EOF
[mysql80-community]
name=MySQL 8.0 Community Server
baseurl=http://repo.mysql.com/yum/mysql-8.0-community/el/9/\$basearch/
enabled=1
gpgcheck=0
EOF

# MySQL 서버 및 개발 라이브러리 설치
echo "MySQL 서버 및 개발 패키지 설치 중..."
dnf module disable mysql -y || true
dnf install -y mysql-community-server mysql-community-devel gcc python3-devel --nogpgcheck

# 비밀번호 정책 설정
echo "MySQL 설정 파일 생성 중..."
cat > /etc/my.cnf.d/mysql-custom.cnf << EOF
[mysqld]
validate_password.policy=LOW
validate_password.length=4
validate_password.mixed_case_count=0
validate_password.number_count=0
validate_password.special_char_count=0
bind-address = 0.0.0.0
EOF

# MySQL 서비스 시작
echo "MySQL 서비스 시작 중..."
systemctl start mysqld || {
    echo "MySQL 서비스 시작 실패"
    journalctl -xe --unit=mysqld
    exit 1
}
systemctl enable mysqld

# 서비스 시작 대기
echo "MySQL 초기화 대기 중..."
sleep 15

# 초기 root 비밀번호 가져오기
echo "초기 비밀번호 확인 중..."
TEMP_PASSWORD=$(grep 'temporary password' /var/log/mysqld.log | awk '{print $NF}')
if [ -z "$TEMP_PASSWORD" ]; then
echo "임시 비밀번호를 찾을 수 없습니다. MySQL 로그를 확인해주세요."
cat /var/log/mysqld.log
    exit 1
fi

echo "MySQL 초기 설정 중..."
mysql --connect-expired-password -u root -p"${TEMP_PASSWORD}" << EOF || exit 1
ALTER USER 'root'@'localhost' IDENTIFIED BY '${ROOT_PASS}';
SET GLOBAL validate_password.policy=LOW;
SET GLOBAL validate_password.length=4;
SET GLOBAL validate_password.mixed_case_count=0;
SET GLOBAL validate_password.number_count=0;
SET GLOBAL validate_password.special_char_count=0;
CREATE DATABASE IF NOT EXISTS ${DB_NAME};
CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
CREATE USER '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'%';
FLUSH PRIVILEGES;
EXIT
EOF

# Django 프로젝트 설정
echo "Django 프로젝트 설정 중..."
mkdir -p /var/log/ecommerce

# .env 파일 생성
cat > .env << EOF
ENGINE='django.db.backends.mysql'
NAME='ecommerce'
DBUSER='testuser'
PASSWORD='testuser'
HOST='localhost'
PORT='3306'
PERSONALIZE_ARN=''
EOF

if ! command -v git &> /dev/null; then
    echo "Git not found. Installing git..."
    dnf install -y git
fi

# Git 저장소 클론 및 환경 설정
git clone https://github.com/color275/workshop-ecommerce
mysql -u ${DB_USER} -p${DB_PASS} ecommerce < workshop-ecommerce/ecommerce.sql
