# AWS EC2 deployment (Ubuntu 24.04)

This deploys SYE Lodge on **one EC2 instance** with PostgreSQL installed locally.
It is the recommended alternative to Render: no container sleep, no 30-day
database expiry, uploads persist on the instance, and the site gets a fresh IP
address with no history from the old `onrender.com` URL.

> AWS Free Tier requires a credit card and lasts 12 months. Set the billing
> alarm in step 2 before launching anything.

## 1. What gets installed

- Ubuntu 24.04 LTS, `t3.micro` (1 GB RAM, 2 vCPU)
- Temurin Java 25
- PostgreSQL (database `sye_lodge`, user `sye_lodge_app`)
- Nginx reverse proxy: port 80 → `127.0.0.1:8080`
- systemd service `sye-lodge` running the Spring Boot JAR
- Demo data: 18 listings (12 featured), student-board posts, five demo accounts

Files in this folder:

| File | Purpose |
| --- | --- |
| `setup.sh` | One-time install on a fresh EC2 instance |
| `sye-lodge.service` | systemd unit for the Java application |
| `nginx.conf` | HTTP reverse proxy site |

## 2. Before launching

1. In AWS **Billing** → **Billing Preferences**, enable free-tier usage alerts.
2. In **Billing** → **Budgets**, create a **$1 cost budget** that emails you.
3. Create an EC2 **key pair** (.pem) and keep it private.

## 3. Launch the instance

- AMI: **Ubuntu Server 24.04 LTS (HVM), SSD Volume Type**
- Instance type: **t3.micro**
- Storage: 15–20 GB gp3
- Security group inbound rules:

| Type | Port | Source | Why |
| --- | --- | --- | --- |
| SSH | 22 | **My IP** | Admin access |
| HTTP | 80 | `0.0.0.0/0` and `::/0` | Public site |
| HTTPS | 443 | `0.0.0.0/0` and `::/0` | Only when a domain is added later |

Restrict SSH to your own IP; never open it to the world.

## 4. Run the setup

Connect from PowerShell:

```powershell
ssh -i "C:\path\to\key.pem" ubuntu@<public-ip>
```

On the instance:

```bash
sudo apt-get update
sudo apt-get install -y git
git clone https://github.com/La-Pulga-001/SYE-Lodge.git ~/SYE-Lodge
chmod +x ~/SYE-Lodge/aws/setup.sh
cd ~/SYE-Lodge
sudo ./aws/setup.sh
```

The script detects the public IP, creates the database user and database,
generates a random `DB_PASSWORD` and `JWT_SECRET`, writes
`/etc/sye-lodge.env` (mode `0600`), clones the repo into `/opt/sye-lodge`,
builds the JAR, installs the service and reloads Nginx.

Open:

```text
http://<public-ip>
```

Run `./aws/setup.sh` **only once**. It deletes and reclones `/opt/sye-lodge`;
use the update steps below for later deploys.

## 5. Verify

```bash
curl -sS http://localhost/api/universities
sudo systemctl status sye-lodge --no-pager
sudo journalctl -u sye-lodge -n 100 --no-pager
```

Useful logs:

```bash
sudo journalctl -u sye-lodge -f
sudo tail -f /opt/sye-lodge/logs/sye_lodge.log
sudo tail -f /var/log/nginx/access.log
```

## 6. Demo accounts

Password for all of these: `Demo@1234`

| Role | Email |
| --- | --- |
| Student | `kwame.student@sye_lodge.test` |
| Student | `abena.student@sye_lodge.test` |
| Student | `yaw.student@sye_lodge.test` |
| Approved landlord | `ama.landlord@sye_lodge.test` |
| Pending landlord | `kofi.landlord@sye_lodge.test` |

The three original administrators (`fblesselikem@gmail.com`,
`ayensusamuel866@gmail.com`, `deiyeshua05@gmail.com`) activate their accounts at
`http://<public-ip>/admin-setup.html`. Because `MAIL_MODE=console`, setup codes
and OTPs appear in the service log:

```bash
sudo journalctl -u sye-lodge -f
```

## 7. Updating the site after a GitHub push

```bash
sudo git -C /opt/sye-lodge pull origin main
sudo bash -c 'cd /opt/sye-lodge && ./mvnw -B -DskipTests package'
sudo chown -R syelodge:syelodge /opt/sye-lodge
sudo systemctl restart sye-lodge
```

Nginx needs no reload for application changes.

## 8. Later: add a domain and HTTPS

The site is HTTP-only until a domain is attached.

1. Buy a domain and add an **A record** pointing to the EC2 public IP.
2. Open port 443 in the security group.
3. On the instance:

```bash
sudo apt-get install -y certbot python3-certbot-nginx
sudo certbot --nginx -d your-domain.example
sudo certbot renew --dry-run
```

4. Update the email-link base URL:

```bash
sudo sed -i 's|^APP_URL=.*|APP_URL=https://your-domain.example|' /etc/sye-lodge.env
sudo systemctl restart sye-lodge
```

5. In Google Search Console, verify the domain with a DNS TXT record at your
   registrar. Do not reuse the old verification file from the previous site.

## 9. Troubleshooting

**App will not start / database errors**

```bash
sudo systemctl status sye-lodge --no-pager
sudo journalctl -u sye-lodge -n 200 --no-pager
sudo -u postgres psql -d sye_lodge -c '\dt'
```

Check that `/etc/sye-lodge.env` has `DB_HOST=localhost`,
`DB_NAME=sye_lodge`, and the `DB_PASSWORD` set by the script.

**502 Bad Gateway**

The app is not listening on 8080 yet. Check `sudo systemctl status sye-lodge`
and the journal; startup with Flyway migrations and demo seeding can take a
minute on a fresh `t3.micro`.

**Out of memory during the Maven build**

The setup script adds a 2 GB swap file and caps the JVM heap at 320 MB. If a
build still fails, add more swap or use `t3.small` temporarily.

**Secrets**

`/etc/sye-lodge.env` is the source of truth. Back it up privately. If you change
`JWT_SECRET`, all existing sign-ins are invalidated.
