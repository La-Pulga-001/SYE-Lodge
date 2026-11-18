# SYE Lodge

SYE Lodge is a student-accommodation platform for Ghana. Students browse approved
listings near their university, compare rent and distance, save favourites,
post roommate requests, comment, and contact landlords directly. Landlords
publish listings after administrator approval. Administrators moderate
accounts, listings and posts and manage each other through an audited
governance flow.

The first supported institution is **Palm University College** (Shai Hills,
Greater Accra). Further institutions can be added from the admin workspace
without redeploying.

- Currency: Ghana cedi (GH₵)
- Payments: none. SYE Lodge only provides direct call/WhatsApp/email contact.
- Backend: Java 25, Spring Boot 3.5.6, PostgreSQL 18
- Frontend: plain HTML, CSS and JavaScript served by Spring Boot (no build step)

---

## 1. Repository layout

```
sye-lodge-common/       enums, DTO records, shared exceptions and geo helpers
sye-lodge-persistence/  JPA entities, repositories, specifications, Flyway SQL
sye-lodge-service/      business logic: auth, OTP, email, storage, audit, admin
sye-lodge-web/          Spring Boot app, REST controllers, security, static UI
aws/                   AWS EC2 setup script, systemd unit, Nginx config, guide
docs/API.md            endpoint reference
docs/RENDER.md         Render Blueprint deployment guide (alternative)
render.yaml            Render Blueprint (web service + PostgreSQL)
Dockerfile             multi-stage production image
docker-entrypoint.sh   container entrypoint (drops privileges)
.env.example           environment variable template
run-dev.bat            local Windows launcher (port 8081)
```

---

## 2. Roles and rules

**Student**
- Browse, search, filter and sort approved listings
- Save listings and posts
- Create, edit and delete their own roommate posts
- Comment on posts and delete their own comments
- Contact landlords (phone, WhatsApp, email) when signed in

**Landlord**
- Browse and search approved listings
- Create and edit their own listings
- Upload up to 10 photos per listing (JPEG, PNG or WebP, max 5 MB each)
- Pin an exact location on the Leaflet/OpenStreetMap picker
- Cannot publish until an administrator approves the landlord account
- Every new or edited listing is reset to `PENDING_APPROVAL`
- No access to saved homes or the student board; those are student-only spaces

**Administrator**
- View users and statistics
- Approve or reject landlord accounts
- Approve, reject, suspend and restore listings
- Hide or restore posts; hide or remove comments
- Suspend and reactivate accounts
- Add and update institutions
- View the audit trail
- Original administrators only: invite administrators, promote existing users,
  revoke administrator access

Safety rules:
- Administrator accounts cannot be suspended.
- The last active administrator and the last original administrator cannot be
  removed.
- Self-revocation is blocked.
- Revoking an admin returns them to `LANDLORD` if they own listings, otherwise
  `STUDENT`.
- Every moderation and governance action is written to the audit log.

Statuses:
- Users: `PENDING_APPROVAL`, `ACTIVE`, `REJECTED`, `SUSPENDED`
  (students are `ACTIVE` immediately; landlords begin as `PENDING_APPROVAL`)
- Listings: `PENDING_APPROVAL`, `APPROVED`, `REJECTED`, `SUSPENDED`, `REMOVED`
- Posts/comments: `VISIBLE`, `HIDDEN`, `REMOVED`

---

## 3. License and ownership

Built for Palm University College and the Ghanaian student-housing market.
Third-party services: Leaflet (BSD-2-Clause), OpenStreetMap/Nominatim usage
policy applies to geocoding and map tiles.

---

## 4. Deployment

The recommended production deployment is a single AWS EC2 `t3.micro` running
Ubuntu 24.04, Java 25, PostgreSQL and Nginx. See
[aws/README.md](aws/README.md) for the complete guide: instance launch,
security group, one-time setup script, logs, billing alarm, updates after a
push, and adding a domain with free HTTPS later. Without a domain the site is
HTTP-only at the EC2 public IP.

The Render Blueprint in `render.yaml` and [docs/RENDER.md](docs/RENDER.md)
remain available as an alternative, but Render accounts have been suspended,
so AWS EC2 is the current target.

Demo accounts use the password `Demo@1234`:

| Role | Email |
| --- | --- |
| Student | `kwame.student@sye_lodge.test` |
| Student | `abena.student@sye_lodge.test` |
| Student | `yaw.student@sye_lodge.test` |
| Approved landlord | `ama.landlord@sye_lodge.test` |
| Pending landlord | `kofi.landlord@sye_lodge.test` |

The AWS setup script and the Blueprint both set `DEMO_DATA=true` and
`DEMO_PASSWORD=Demo@1234`. Set `DEMO_DATA=false` for an empty catalogue.
The original administrators
(`fblesselikem@gmail.com`, `ayensusamuel866@gmail.com`,
`deiyeshua05@gmail.com`) activate their accounts at `/admin-setup.html`.
