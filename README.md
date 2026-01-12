🗑️ Uninstall

Untuk menghapus Bandix Dashboard:

```bash
#!/bin/sh
rm -rf /www/bandix
rm -f /www/cgi-bin/bandix-api
echo "Bandix Dashboard telah dihapus"
```

---

## 📝 Fitur

- ✅ Dashboard real-time dengan auto-refresh
- ✅ Monitoring CPU, RAM, Temperature
- ✅ Daftar perangkat yang terhubung
- ✅ Bandwidth monitoring dengan grafik
- ✅ Informasi jaringan (WAN/LAN/WiFi)
- ✅ Quick actions (Reboot, Restart WiFi)
- ✅ Desain modern dengan dark theme
- ✅ Responsive untuk mobile

---

## ⚠️ Catatan Penting

1. **Pastikan router memiliki koneksi internet** saat instalasi untuk mengunduh dependensi
2. **Backup konfigurasi** router sebelum instalasi
3. Dashboard menggunakan **TailwindCSS CDN**, membutuhkan internet untuk styling optimal
4. Untuk mode **offline penuh**, download dan host file CSS/JS lokal

---

## 🆘 Troubleshooting

**Dashboard tidak muncul:**
```bash
# Restart uhttpd
/etc/init.d/uhttpd restart
```

**API tidak bekerja:**
```bash
# Cek permission
chmod +x /www/cgi-bin/bandix-api
```

**Error "Permission denied":**
```bash
# Jalankan sebagai root
su -c '/tmp/install-bandix.sh'
```
