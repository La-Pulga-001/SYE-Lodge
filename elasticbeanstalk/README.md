# Elastic Beanstalk deployment

This deploys SYE Lodge on the **Java SE platform** (`Corretto 25` on Amazon
Linux 2023) with a coupled **PostgreSQL** database from Amazon RDS. The
platform builds the Spring Boot JAR on the instance, so you do **not** need
Java or Maven installed locally.

The site is demo-ready: 18 listings (12 featured), student-board posts, and
five working demo accounts. Email is console-only, so OTP and administrator
setup codes appear in the environment logs.

> AWS Free Tier requires a credit card and lasts 12 months. Create a **$1
> billing alarm/budget** before launching.

## Files in this kit

| File | Purpose |
| --- | --- |
| `../Buildfile` | Builds the JAR on-instance with Maven and copies it to `application.jar` |
| `../Procfile` | Runs `java -jar application.jar` on the EB app process |
| `../.ebextensions/01-environment.config` | Env vars, instance type, health check, log streaming, timeout |
| `../.ebextensions/02-instance.config` | 2 GB swap, demo-photo fonts, persistent upload directory |
| `../.platform/nginx/conf.d/elasticbeanstalk/01-uploads.conf` | Raises nginx upload limit to 25 MB |
| `../.ebignore` | Keeps the source bundle small |
| `../.elasticbeanstalk/config.yml` | EB CLI application name, platform and region |
| `create.ps1` | Creates the environment, RDS database and secrets |
| `set-env.ps1` | Updates `APP_URL` and/or `JWT_SECRET` later |
| `README.md` | This guide |

`application.yml` also falls back to EB's `RDS_HOSTNAME`, `RDS_PORT`,
`RDS_DB_NAME`, `RDS_USERNAME` and `RDS_PASSWORD`, so no database credentials
are stored in the repository.

## 1. Prerequisites

1. Install the EB CLI and AWS CLI, then configure credentials:

```powershell
python -m pip install awsebcli awscli
aws configure
```

The IAM user needs permissions for Elastic Beanstalk, EC2, RDS, S3 and IAM
role creation. If you use a named profile, set `$env:AWS_EB_PROFILE` to it.

2. Create a $1 AWS Budget that emails you.

3. From the repo root, check the EB CLI reads the project config:

```powershell
cd C:\Users\USER\Desktop\SYE-Lodge-Clean
eb status
```

## 2. Create the environment

Run the create script once from the repo root:

```powershell
.\elasticbeanstalk\create.ps1
```

It will:

- create application `sye-lodge` and environment `sye-lodge-prod`
- select `Corretto 25 running on 64bit Amazon Linux 2023`
- launch one `t3.micro` instance (no load balancer)
- create a coupled `db.t3.micro` PostgreSQL database (5 GB)
- generate a 96-character `JWT_SECRET`
- set `APP_URL=http://sye-lodge-prod.elasticbeanstalk.com`
- prompt you for an RDS master password (8–16 characters, no `/`, `\`, `@`)
- set all demo and Spring settings from `.ebextensions/01-environment.config`

The password and JWT secret are **not** saved in the repo. Store them privately.

If you need a different region or CNAME:

```powershell
.\elasticbeanstalk\create.ps1 -Region eu-central-1 -CName sye-lodge-demo -EnvironmentName sye-lodge-demo
```

Then update `APP_URL` in `.ebextensions/01-environment.config` to match the
CNAME before deploying again.

## 3. Verify

```powershell
eb status
eb health
eb logs
```

Open:

```text
http://sye-lodge-prod.elasticbeanstalk.com
```

Check the API directly:

```powershell
curl.exe http://sye-lodge-prod.elasticbeanstalk.com/api/universities
```

The first deploy takes several minutes: RDS creation, Maven build, Flyway
migrations and demo seeding.

## 4. Demo accounts

Password for all: `Demo@1234`

| Role | Email |
| --- | --- |
| Student | `kwame.student@sye_lodge.test` |
| Student | `abena.student@sye_lodge.test` |
| Student | `yaw.student@sye_lodge.test` |
| Approved landlord | `ama.landlord@sye_lodge.test` |
| Pending landlord | `kofi.landlord@sye_lodge.test` |

Original administrators (`fblesselikem@gmail.com`, `ayensusamuel866@gmail.com`,
`deiyeshua05@gmail.com`) activate accounts at
`/admin-setup.html`. With `MAIL_MODE=console`, codes appear in:

```powershell
eb logs
```

## 5. Deploy updates

After pushing to GitHub, run from the repo root:

```powershell
eb deploy
```

The platform rebuilds the JAR and restarts the app. Uploaded listing photos
live in `/var/app/data/uploads` and survive ordinary application deploys on
the single instance.

## 6. Secrets and email links

`APP_URL` controls links in OTP and password-reset emails. After adding a
custom domain or changing the CNAME:

```powershell
.\elasticbeanstalk\set-env.ps1 -AppUrl "https://your-domain.example"
```

To rotate the signing secret (this signs out all users):

```powershell
.\elasticbeanstalk\set-env.ps1 -JwtSecret "<new-long-random-secret>"
```

To enable real email later, set `MAIL_MODE=resend`, `RESEND_API_KEY` and a
verified `MAIL_FROM` with `eb setenv`.

## 7. Later: custom domain and HTTPS

The environment is HTTP-only at its `elasticbeanstalk.com` address. To add
HTTPS:

1. Create an ACM certificate in **us-east-1** for your domain (or in the
   environment's region if you use a dedicated ALB).
2. Recreate the environment as Load Balanced with an Application Load Balancer
   and add an HTTPS listener with that certificate.
3. Point your domain's CNAME at the EB CNAME.
4. Update the email base URL:

```powershell
.\elasticbeanstalk\set-env.ps1 -AppUrl "https://your-domain.example"
```

5. Verify the domain in Google Search Console with a DNS TXT record at your
   registrar. Do not reuse any old verification file.

## 8. Troubleshooting

**App exits with a JWT error**

`JWT_SECRET` is missing. Set it:

```powershell
.\elasticbeanstalk\set-env.ps1 -JwtSecret "<long-random-secret>"
```

**Flyway cannot connect to the database**

Check that the environment was created with a database:

```powershell
eb config
```

Look for `RDS_HOSTNAME`, `RDS_PORT`, `RDS_DB_NAME`, `RDS_USERNAME` and
`RDS_PASSWORD` in Environment Properties.

**Build or deploy times out**

`.ebextensions/01-environment.config` raises the command timeout to 1800
seconds and `02-instance.config` adds 2 GB of swap. Check:

```powershell
eb events
eb logs
```

**502 / unhealthy environment**

`eb logs` shows Spring Boot startup. Watch for Flyway migration errors,
missing `JWT_SECRET`, or port mismatch. The app must listen on `PORT=5000`,
which is set by the config file.

**Uploads larger than 1 MB are rejected**

Confirm `.platform/nginx/conf.d/elasticbeanstalk/01-uploads.conf` is present
in the source bundle and redeploy with `eb deploy`.
