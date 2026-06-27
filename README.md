# MobilePC Media

MobilePC Media adalah aplikasi remote control PC Windows dari HP Android berbasis Flutter. Aplikasi ini terhubung ke server Python di PC melalui jaringan lokal, lalu HP dapat dipakai sebagai touchpad, keyboard live typing, voice typing, audio receiver, dan viewer layar PC.

## Fitur

- Trackpad HP untuk gerak mouse, klik kiri, klik kanan, scroll, dan gesture browser.
- Live typing dari keyboard HP langsung ke PC.
- Voice typing: tahan tombol mic, bicara, lalu teks dikirim ke PC.
- Tombol cepat seperti Alt+Tab, Enter, Backspace, Refresh, Copy, dan Paste.
- Stream audio PC ke HP.
- Screen mirror PC ke HP dengan kontrol sentuh langsung.
- Auto-discovery server PC lewat tombol search, atau koneksi manual via IP address.

## Screenshot

![Sampel 1](Sampel%201.jpeg)

![Sampel 2](Sampel%202.png)

## Cara Pakai

1. Pastikan HP dan PC Windows berada di jaringan Wi-Fi/LAN yang sama.
2. Jalankan server Python di PC:

   ```bat
   run_server.bat
   ```

   Atau manual:

   ```bat
   cd python_server
   python server.py
   ```

3. Di window server PC, klik **START**. Catat IP address yang muncul.
4. Buka aplikasi Android.
5. Tekan icon kaca pembesar untuk auto-scan server PC.
6. Jika auto-scan gagal, masukkan IP address dari window server secara manual, lalu tekan **Connect**.
7. Setelah terhubung, gunakan touchpad, live typing, voice typing, audio toggle, atau tombol **Mirror** untuk melihat dan mengontrol layar PC.

## Instalasi

### Server PC

Install Python 3.10+ di Windows, lalu install dependency:

```bat
cd python_server
python -m pip install -r requirements.txt
```

Jika Windows Firewall meminta izin, pilih **Allow access** agar HP bisa terhubung ke server.

Port yang digunakan:

- `8080` TCP untuk command/control.
- `8081` UDP untuk discovery dan audio stream.
- `8082` TCP untuk screen mirror.

### Aplikasi Android

Build dari folder Flutter:

```bat
cd flutter_client
flutter pub get
flutter build apk
```

APK hasil build ada di:

```text
flutter_client/build/app/outputs/flutter-apk/app-release.apk
```

## Catatan

- Aplikasi ini ditujukan untuk penggunaan di jaringan lokal pribadi.
- Jalankan server Python hanya saat ingin mengontrol PC.
- Performa audio dan screen mirror bergantung pada kualitas jaringan Wi-Fi.
