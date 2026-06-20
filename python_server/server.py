import socket
import json
import threading
import pyautogui
import soundcard as sc
import numpy as np

# Konfigurasi Server
HOST = '0.0.0.0'  
PORT = 8080
UDP_PORT = 8081

# Variabel global untuk menyimpan IP Klien yang terhubung (HP Anda)
CLIENT_IP = None
client_ip_lock = threading.Lock()

def audio_streamer():
    global CLIENT_IP
    udp_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    
    try:
        # Mencari speaker utama
        default_speaker = sc.default_speaker()
        # Mencari loopback mic yang sesuai dengan speaker utama
        mics = sc.all_microphones(include_loopback=True)
        loopback_mic = None
        for m in mics:
            if m.isloopback and m.name == default_speaker.name:
                loopback_mic = m
                break
        
        if not loopback_mic:
            loopback_mic = mics[0] # Fallback
            
        print(f"[*] Audio streamer siap merekam dari: {loopback_mic.name}")
        
        # Merekam dengan 16000Hz (Cukup untuk suara/film dan ringan di jaringan)
        with loopback_mic.recorder(samplerate=16000, channels=1) as mic:
            while True:
                data = mic.record(numframes=1024)
                # Konversi data float32 dari soundcard ke int16 (standar PCM untuk Android)
                data_int16 = (data * 32767).astype(np.int16)
                
                with client_ip_lock:
                    target_ip = CLIENT_IP
                
                if target_ip:
                    try:
                        udp_socket.sendto(data_int16.tobytes(), (target_ip, UDP_PORT))
                    except Exception:
                        pass # Abaikan error pengiriman UDP
    except Exception as e:
        print(f"[-] Gagal memulai audio streamer: {e}")

def handle_client(conn, addr):
    global CLIENT_IP
    print(f"[+] Terhubung dengan {addr}")
    
    # Simpan IP Klien agar Audio Streamer tahu kemana harus mengirim suara
    with client_ip_lock:
        CLIENT_IP = addr[0]
        
    buffer = ""
    try:
        while True:
            data = conn.recv(1024)
            if not data:
                break
            
            buffer += data.decode('utf-8')
            while '\n' in buffer:
                line, buffer = buffer.split('\n', 1)
                line = line.strip()
                if not line:
                    continue
                
                try:
                    command = json.loads(line)
                    execute_command(command)
                except json.JSONDecodeError:
                    pass
                except Exception as e:
                    print(f"[-] Gagal mengeksekusi perintah: {e}")

    except ConnectionResetError:
        print(f"[-] Koneksi terputus dari {addr}")
    finally:
        conn.close()
        print(f"[-] Klien {addr} terputus")
        with client_ip_lock:
            if CLIENT_IP == addr[0]:
                CLIENT_IP = None # Reset IP jika klien ini terputus

def execute_command(cmd):
    action_type = cmd.get("type")
    
    if action_type == "MOUSE_MOVE":
        dx = cmd.get("dx", 0)
        dy = cmd.get("dy", 0)
        pyautogui.moveRel(dx, dy)
        
    elif action_type == "MOUSE_CLICK":
        button = cmd.get("button", "left")
        pyautogui.click(button=button)
        
    elif action_type == "TYPE_TEXT":
        text = cmd.get("text", "")
        if text:
            pyautogui.write(text, interval=0.01)

def start_server():
    pyautogui.FAILSAFE = False
    
    # Jalankan Audio Streamer di thread terpisah (berjalan terus menerus)
    audio_thread = threading.Thread(target=audio_streamer, daemon=True)
    audio_thread.start()
    
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.bind((HOST, PORT))
    server.listen(5)
    print(f"[*] Server Kontrol berjalan di {socket.gethostbyname(socket.gethostname())}:{PORT}")
    print("[*] Menunggu koneksi dari klien...")
    
    try:
        while True:
            conn, addr = server.accept()
            client_thread = threading.Thread(target=handle_client, args=(conn, addr))
            client_thread.start()
    except KeyboardInterrupt:
        print("\n[*] Server dimatikan.")
    finally:
        server.close()

if __name__ == "__main__":
    start_server()
