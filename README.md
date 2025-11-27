# VibeArena Infra (Dev/Prod)

로컬 개발·스테이징·프로덕션을 동일한 패턴으로 운영할 수 있는 경량 인프라 표준을 제공.<br>
구성은 Docker Compose(개발/스테이징)와 IaC(선택: Terraform/Ansible)로 분리 가능하며, Nginx 리버스 프록시, Django API, Celery(Worker/Beat), Postgres, Redis, MinIO/S3, 모니터링 스택(Prometheus/Grafana)을 기본 프로파일로 제공한다.

## 0) 팀 규칙

- 문서가 코드보다 먼저. 기획서 → SDS → 코드 → 리뷰 → README 반영. “말로만 있는 규칙”은 규칙 아님.

- 언어/도구 컨벤션 준수. Python=PEP8, TS=ESLint/Prettier 등. 이름은 명확하게.

- Vibe Coding OK, 단 “왜 그렇게 했는지” 설명 가능해야 함.

- Free Tier 정신. 단순/가벼움/유지보수성 우선, 과한 의존성 금지.

- PR 리뷰 필수, 테스트 동반. main에 직접 푸시 금지. 브랜치 feature/, fix/, refactor/.

- Secrets 분리, 로깅 시 개인정보 마스킹, 권한 로직은 예외/검증 필수.

- 주석은 “왜”를 설명. 과장/장식/AI 흔적 금지.

- 의사결정=로그+결론+근거. 기록과 회고를 통해 성장.

## 1) 파일 구조

```
infra/
├─ compose/
│  ├─ core/               # 내부 스택(Postgres/Redis/Celery/Observability)
│  └─ edge/               # 외부 노출 스택(nginx + Django web)
├─ env/
│  ├─ .env.core.example   # Core VM용 컨테이너 환경 템플릿
│  └─ .env.edge.example   # Edge VM용 컨테이너 환경 템플릿
├─ ops/
│  ├─ nginx/              # reverse proxy + TLS 설정
│  ├─ otel/               # OpenTelemetry collector 파이프라인
│  ├─ prometheus/         # Prometheus 스크레이프 설정
│  ├─ loki/               # Loki 로컬 저장소 설정
│  └─ certs/              # nginx 컨테이너가 참조할 TLS 인증서 위치
├─ scripts/
│  ├─ bootsrtap_common.sh # Ubuntu VM 부트스트랩(Docker+UFW)
│  ├─ deploy_core.sh      # Core compose 배포
│  └─ deploy_edge.sh      # Edge compose 배포
└─ README.md
```

> 각 compose 디렉터리에는 Compose가 치환할 `.env`(예: `compose/core/.env`) 파일을 별도로 둔다. 컨테이너 내부로 주입할 값은 `env/.env.*`에서 관리한다.
## 2) 서비스 토폴로지(기본 프로파일)

- **Core VM**: Postgres, Redis, MinIO/S3, Celery Worker/Beat, Executor, Observability(OTel → Prometheus/Grafana, Loki). 외부에서 직접 접근하지 않고 Edge에서만 사설망으로 통신.
- **Edge VM**: nginx reverse proxy(:443)와 Django 웹 컨테이너만 배치. nginx는 TLS 종료 및 보안 헤더, Django는 gunicorn으로 운영.
- 원칙: “Public은 nginx 하나, 나머지는 모두 내부 네트워크”. 관측·백업·배치 자동화를 Core에 집중시켜 Edge는 경량 상태를 유지.

## 3) 빠른 시작 (Core/Edge 재현)

Core와 Edge는 서로 다른 VM(또는 Docker Desktop VM)에서 실행한다고 가정한다.

### Core
1. Compose 치환 변수 작성: `compose/core/.env`에 `WEB_IMAGE`, `EXECUTOR_IMAGE`, `MINIO_ACCESS_KEY`, `MINIO_SECRET_KEY` 등 값을 정의.
2. 컨테이너 환경 템플릿 복사: `cp env/.env.core.example env/.env.core` 후 실제 DB/S3/Telemetry 정보를 채운다.
3. 배포: `./scripts/deploy_core.sh` (또는 `cd compose/core && docker compose up -d`).
4. 상태 확인: `docker compose ps`, Grafana `:3000`, Prometheus `:9090`, Loki `:3100`, OTel gRPC `:4317`.

### Edge
1. Compose 치환 변수 작성: `compose/edge/.env`에 `WEB_IMAGE`, `EXECUTOR_IMAGE`(필요 시) 등을 정의.
2. 컨테이너 환경 템플릿 복사: `cp env/.env.edge.example env/.env.edge` 후 도메인, Core VM 사설 IP, S3 자격증명 등을 채운다.
3. TLS 인증서 배치: `ops/certs/{fullchain.pem,privkey.pem}`에 파일을 두거나 심볼릭 링크로 연결.
4. 배포: `./scripts/deploy_edge.sh` (또는 `cd compose/edge && docker compose up -d`).
5. 상태 확인: `docker compose ps`, nginx health `https://<DOMAIN>/nginx/health`, Django `https://<DOMAIN>/admin/`.

## 4) 환경변수(.env)

| 위치 | 용도 | 주요 키 |
| --- | --- | --- |
| `compose/*/.env` | Docker Compose가 `${VAR}`를 치환할 때 사용. VM 운영자가 직접 관리. | `WEB_IMAGE`, `EXECUTOR_IMAGE`, `MINIO_ACCESS_KEY`, `MINIO_SECRET_KEY` 등 |
| `env/.env.core` | Core 컨테이너 내부용 환경. worker/beat/executor/MinIO/Postgres 등에 주입. | `POSTGRES_*`, `DATABASE_URL`, `REDIS_URL`, `MINIO_*`, `OTEL_EXPORTER_OTLP_ENDPOINT`, `SENTRY_DSN` |
| `env/.env.edge` | Edge 컨테이너 내부용 환경. Django 웹/OTel/외부 S3 자격 증명 포함. | `DJANGO_SECRET_KEY`, `DJANGO_ALLOWED_HOSTS`, `DATABASE_URL`, `REDIS_URL`, `S3_*`, `OTEL_EXPORTER_OTLP_ENDPOINT`, `TLS_CERT`, `TLS_KEY` |

- 예시 파일(`*.example`)을 복사해 실 값을 채운 뒤 버전 관리는 예시만 포함한다.
- Google Analytics 등 선택 항목은 Base64 인코딩 후 환경변수로 주입하는 기존 백엔드 패턴을 유지.

## 5) 프로파일

- Core/Edge 두 VM 구성이 기본. 필요 시 Core를 확장해 스테이징/운영 데이터를 분리하거나 Edge를 여러 리전에 복제할 수 있다.
- Dev 환경에서도 Docker Desktop의 두 VM을 활용하면 운영 토폴로지와 거의 동일한 시나리오로 테스트 가능하다.
- IaC(Terraform/Ansible)로 VM을 생성한 뒤 본 저장소의 Compose와 스크립트를 그대로 사용하도록 설계했다.

## 6) 배포 전략

- CI: 애플리케이션 리포에서 Lint/TypeCheck/Test 후 Web/Executor 이미지를 빌드해 레지스트리에 푸시.
- CD: Core/Edge VM에 SSH 접속 후 `scripts/deploy_core.sh`/`scripts/deploy_edge.sh`를 실행하도록 GitHub Actions나 다른 러너에서 오케스트레이션.
- TLS/Secrets는 각각 VM의 `.env`와 `ops/certs` 마운트로 공급. Core ↔ Edge 사이 통신은 사설 IP 또는 VPN/터널로 보호.

## 7) 보안·백업

Secrets는 .env/CI secret으로만 관리(코드 금지).

TLS: dev는 mkcert/自서명, prod는 ACME(Let’s Encrypt) 자동화.

백업: Core VM에서 Postgres/MinIO 볼륨 스냅샷 또는 별도 스크립트를 주기적으로 실행(예: cron, GitHub Actions runner). 필요 시 `docker exec postgres pg_dump` 방식으로 외부 백업.

로그/모니터링: OTel Collector → Prometheus/Grafana로 메트릭 수집, Loki로 로그 저장. Edge nginx/Django 로그도 Loki로 보낼 수 있도록 추가 파이프라인 구성 권장.

## 8) 운영 스크립트

- `scripts/bootsrtap_common.sh`: Ubuntu VM에 Docker/Compose/UFW를 설치하고 방화벽 규칙(22/80/443)을 기본 적용.
- `scripts/deploy_core.sh`: Core 디렉터리로 이동해 env 파일 존재 여부 확인 후 `docker compose pull/up`.
- `scripts/deploy_edge.sh`: Edge 디렉터리에서 동일 절차 수행.
- 필요 시 이 스크립트를 CI/CD에서 호출하거나, Ansible/SSH 원격 실행 훅에 연결.
## 9) 트러블슈팅

- 컨테이너가 즉시 종료 → `docker compose logs <service>`로 crash 지점을 확인하고 env 키/이미지 태그/볼륨 권한을 점검한다.
- nginx 502 → Django health(`/health`) 확인, Core ↔ Edge 네트워크/보안그룹 점검, TLS 파일 권한 확인.
- Celery worker 기동 실패 → 사용 중인 이미지에 `celery` 바이너리가 포함됐는지, Redis/DB 접속 정보가 정확한지 확인.
- OTel/Prometheus 지표 누락 → Core의 `ops/otel/otel.yaml`과 포트(4317/9464) 개방 여부 확인.
- 인증/권한 실패 로그는 PII를 마스킹해 공유한다.
