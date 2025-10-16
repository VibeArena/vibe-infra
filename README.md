# VibeArena Infra (Dev/Prod)

목표: 로컬 개발·스테이징·프로덕션을 동일한 패턴으로 운영할 수 있는 경량 인프라 표준을 제공한다.
구성은 Docker Compose(개발/스테이징)와 IaC(선택: Terraform/Ansible)로 분리 가능하며, Nginx 리버스 프록시, Django API, Celery(Worker/Beat), Postgres, Redis, MinIO/S3, 모니터링 스택(Prometheus/Grafana)을 기본 프로파일로 제공한다.
---

0) 팀 규칙 요약 (README 공통 축약본)

문서가 코드보다 먼저. 기획서 → SDS → 코드 → 리뷰 → README 반영. “말로만 있는 규칙”은 규칙 아님.

언어/도구 컨벤션 준수. Python=PEP8, TS=ESLint/Prettier 등. 이름은 명확하게.

Vibe Coding OK, 단 “왜 그렇게 했는지” 설명 가능해야 함.

Free Tier 정신. 단순/가벼움/유지보수성 우선, 과한 의존성 금지.

PR 리뷰 필수, 테스트 동반. main에 직접 푸시 금지. 브랜치 feature/, fix/, refactor/.

Secrets 분리, 로깅 시 개인정보 마스킹, 권한 로직은 예외/검증 필수.

주석은 “왜”를 설명. 과장/장식/AI 흔적 금지.

의사결정=로그+결론+근거. 기록과 회고를 통해 성장.
---
1) 레포 구조
infra/
├─ compose/
│  ├─ dev/                # 로컬 개발용(docker-compose.dev.yml)
│  ├─ stage/              # 스테이징(docker-compose.stage.yml)
│  └─ prod/               # 프로덕션(docker-compose.prod.yml)
├─ config/
│  ├─ nginx/              # reverse-proxy conf (rate limit, body size)
│  ├─ grafana/            # dashboards & datasources
│  ├─ prometheus/         # scrape configs (api, worker, nginx)
│  └─ loki/ (option)      # log aggregation (선택)
├─ env/
│  ├─ dev.example.env
│  ├─ stage.example.env
│  └─ prod.example.env
├─ scripts/
│  ├─ makecert.sh         # 로컬 TLS (mkcert 등)
│  ├─ wait-for.sh         # compose 의존성 대기
│  └─ backup_*.sh         # pg/minio 백업 스크립트
├─ Makefile               # 편의 타스크
└─ README.md
---
2) 서비스 토폴로지(기본 프로파일)

Nginx (:443)만 퍼블릭. API/DB/Redis/MinIO는 내부 네트워크만.

Django API(gunicorn), Celery worker/beat, Postgres, Redis, MinIO(S3 호환), Prometheus/Grafana.

“외부는 Nginx만, 내부 리소스는 내부 전용” 보안 경계 원칙을 상시 유지.
---
3) 빠른 시작 (로컬 개발)
# 0) 환경변수 세팅
cp env/dev.example.env .env

# 1) 이미지 빌드 & 기동
docker compose -f compose/dev/docker-compose.dev.yml up -d --build

# 2) 초기화
docker compose -f compose/dev/docker-compose.dev.yml exec api python manage.py migrate
docker compose -f compose/dev/docker-compose.dev.yml exec api python manage.py createsuperuser

# 3) 상태 확인
docker compose -f compose/dev/docker-compose.dev.yml ps


기본 포트(예시):

Nginx https://localhost:443 → /api/*는 Django, /static/* 정적, /admin/* 관리자.

Grafana http://localhost:3000 (admin/admin 변경 필수).

MinIO Console http://localhost:9001.
---
4) 환경변수(.env 핵심)
# 공통
ENV=dev
DOMAIN=localhost

# Nginx
NGINX_RATE_LIMIT=10r/s
CLIENT_MAX_BODY_SIZE=50m

# Django/API
DJANGO_SECRET_KEY=...
DJANGO_SETTINGS_MODULE=config.settings.dev
ALLOWED_HOSTS=localhost,127.0.0.1
DATABASE_URL=postgres://user:pass@postgres:5432/app
REDIS_URL=redis://redis:6379/0

# Celery
CELERY_BROKER_URL=${REDIS_URL}
CELERY_RESULT_BACKEND=${REDIS_URL}

# Object Storage
MINIO_ENDPOINT=minio:9000
MINIO_ROOT_USER=...
MINIO_ROOT_PASSWORD=...
MINIO_BUCKET=krvibe

# Observability
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317  # (선택)
GRAFANA_ADMIN_PASS=...

# (선택) Google Analytics Service Account JSON (백엔드에서 사용)
GA_SVC_JSON_BASE64=...   # 환경변수로 인코딩 주입


백엔드는 GA 서비스 계정 JSON을 환경변수로 주입해 통계 API를 호출하는 구조로 설계됨(보안·배포 편의 고려).
---
5) 프로파일

dev: 전체 스택 로컬, volume 마운트, auto-reload.

stage: 실제 배포 이미지 + stage 비밀/도메인, 데이터는 스테이징 격리.

prod: 최소 구성(Nginx, API, Worker/Beat, Postgres, Redis, MinIO, 모니터링). 리소스/보안 한층 강화.
---
6) 배포 전략

Render(정적/웹서비스) 또는 AWS EC2(+Docker Compose) 를 기본 경로로 상정.

GitHub Actions:

CI: Lint/TypeCheck/Test → 이미지 빌드 → 레지스트리 푸시

CD: 환경별 compose 파일로 원격 배포(ssh-run 또는 Render Deploy Hook)
---
7) 보안·백업

Secrets는 .env/CI secret으로만 관리(코드 금지).

TLS: dev는 mkcert/自서명, prod는 ACME(Let’s Encrypt) 자동화.

백업: scripts/backup_postgres.sh, scripts/backup_minio.sh 주기 실행(cron/Actions).

로그/모니터링: Prometheus Scrape, Grafana 대시보드, (선택) Loki/Promtail.
---
8) Make 타스크(예)
up:         ## dev up
	docker compose -f compose/dev/docker-compose.dev.yml up -d

down:       ## dev down
	docker compose -f compose/dev/docker-compose.dev.yml down

logs:       ## tail logs
	docker compose -f compose/dev/docker-compose.dev.yml logs -f --tail=200

rebuild:    ## build no cache
	docker compose -f compose/dev/docker-compose.dev.yml build --no-cache

9) 트러블슈팅

컨테이너가 즉시 종료 → logs로 crash 지점 확인, env 오타 점검.

Nginx 502 → API health 확인(마이그레이션/DB 연결), proxy_pass 경로 점검.

인증/권한 실패 로그는 PII 마스킹 후 공유.
