# LG 50UN73006LA Upgrade Suite

**TV:** LG 50UN73006LA — webOS 5.0 (2020)  
**TV IP:** 192.168.0.158 | **Dev Mode Passphrase:** 5D6431

---

## Архітектурний план та результати R&D

### Огляд вразливостей та методів рутування

| Метод | Версія webOS | Ризик | Оборотність | Статус |
|-------|-------------|-------|-------------|--------|
| **DejaVuln / CVE-2023-6319** (рекомендовано) | 3.5–5.5 | Низький | Повна | USB trigger |
| RootMyTV v2 | 4.x–5.x | Низький | Повна | Може бути запатчено |
| Developer Mode only | Будь-яка | Нульовий | — | Вже активно |

**Підтверджені вразливі версії для CVE-2023-6319:** 4.9.7, **5.5.0**, 6.3.3, 7.3.1  
Вашій моделі (2020, webOS 5.0) відповідає діапазон 5.x — найімовірніше вразлива.  
**Перед USB-процедурою:** перевірте на https://canI.rootmy.tv

---

### Порівняльна матриця підходів

| Підхід | Приватність | Продуктивність | YouTube | OTA-блок | Складність |
|--------|------------|----------------|---------|----------|------------|
| Dev Mode only | ★★☆ | ★★☆ | ✓ | ✓ (частково) | Низька |
| Dev Mode + DNS блокінг | ★★★ | ★★☆ | ✓ | ✓ | Низька |
| **Rooted + повний стек** | ★★★★★ | ★★★★★ | ✓ | ✓✓✓ | Середня |

---

## Швидкий старт (одна команда)

```bash
# Клонуйте репо на свій ПК (або скопіюйте папку tv-upgrade/)
git clone https://github.com/igor-zinoviev/bossoflockerroom.git
cd bossoflockerroom/tv-upgrade

# Зробіть скрипти виконуваними
chmod +x *.sh

# Запуск ПОВНОГО pipeline (рекомендовано)
./run_all.sh

# АБО: тільки без рутування
./run_all.sh --no-root

# АБО: лише аудит (read-only, нічого не змінює)
./run_all.sh --audit-only
```

> **Примітка для Windows:** Запускайте з WSL2, Git Bash або PowerShell з OpenSSH.

---

## Покроковий план

### Фаза 0 — Підготовка (одноразово)
```bash
./02_setup_ssh.sh    # Встановлює ares-cli, SSH ключ для TV
```
Потрібно: passphrase `5D6431` показаний на екрані TV в Developer Mode.

### Фаза 1 — Аудит (read-only, без змін)
```bash
./01_audit.sh        # Знімає зліпок: прошивка, RAM, процеси, сокети
./03_root_check.sh   # Визначає метод рутування
```
Результат: `./tv-backup/system_audit.json`

### Фаза 2 — Root (потрібен USB диск FAT32)
```bash
./04_root_usb.sh     # Завантажує payload, інструкції для USB
```
Після вставки USB диску — TV сам виконає exploit (~3 хв) і встановить Homebrew Channel.  
**Перевірка:** `ssh -p 9922 prisoner@192.168.0.158 "id"` → `uid=0(root)`

### Фаза 3 — Backup (обов'язково перед змінами)
```bash
./05_backup.sh       # Дамп прошивки, налаштувань, списку додатків
```

### Фаза 4 — Приватність та ACR
```bash
./06_privacy.sh      # /etc/hosts блокінг ~30 доменів, ACR off, рекламні треккери off
./07_ota_block.sh    # OTA блок (3 рівні) + dev mode auto-renew
```

### Фаза 5 — Прикладний шар
```bash
./08_youtube.sh      # youtube-webos: без реклами, SponsorBlock, 4K/HDR нативно
```

### Фаза 6 — Продуктивність
```bash
./09_performance.sh  # Вимкнення важких preload-сервісів, Quick Start+, zRAM tune
```

### Фаза 7 — Верифікація
```bash
./10_verify.sh       # До/після порівняння: RAM, сокети, заблоковані домени
```

### Відкат
```bash
./rollback.sh        # Повне відновлення до стану до модифікацій
```

---

## Що буде зроблено (підсумок)

| Шар | Дія | Метод | Оборотно |
|-----|-----|-------|---------|
| Приватність | Блок ~30 ACR/telemetry доменів | /etc/hosts | ✓ |
| Приватність | Вимкнення Live Plus (ACR) | Luna API | ✓ |
| Приватність | Opt-out рекламного трекінгу | Luna settings | ✓ |
| OTA | Auto-update OFF | Settings API | ✓ |
| OTA | Блок firmware серверів | /etc/hosts | ✓ |
| Persistence | Dev Mode auto-renew | cron | ✓ |
| YouTube | youtube-webos IPK | ares-install | ✓ |
| Перф. | Quick Start+ | Settings API | ✓ |
| Перф. | Вимкнення preload сервісів | upstart override | ✓ |
| Root | Homebrew Channel | DejaVuln USB | ✓ |

---

## Важливі зауваження

**НЕ торкаємося:**
- Завантажувач і розділи ядра
- Системні розділи `/usr`, `/etc/init` (крім override файлів)
- Акаунти та авторизаційні токени додатків
- Налаштування зображення і звуку
- HDMI входи та пульт

**Dev Mode:**
- Закінчується через ~6 тижнів
- Запускайте `./tv-backup/renew.sh` кожні 5 тижнів
- Або налаштуйте cron: `0 9 1 */5 * ~/bossoflockerroom/tv-backup/renew.sh`

---

## Джерела та виправдання вибору стеку

- [webosbrew.org](https://www.webosbrew.org) — офіційна спільнота homebrew для LG webOS
- [throwaway96/dejavuln-autoroot](https://github.com/throwaway96/dejavuln-autoroot) — USB root (CVE-2023-6319)
- [RootMyTV](https://rootmy.tv) — браузерний root (альтернатива)
- [youtube-webos](https://github.com/webosbrew/youtube-webos) — нативний YouTube без реклами
- [SR-Lut3t1um/Webos-renew-dev](https://github.com/SR-Lut3t1um/Webos-renew-dev) — dev mode renewal
- [AdGuard LG blocklist](https://github.com/elijahchen/lg-webos-adguard-home-blocklist) — domain list
