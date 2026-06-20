import socket
import json
import threading
import pyautogui

# Konfigurasi Server
HOST = '0.0.0.0'  # Mendengarkan semua IP (supaya bisa diakses dari HP via Wi-Fi)
PORT = 8080

def handle_client(conn, addr):
    print(f"[+] Terhubung dengan {addr}")
    # Buffer untuk menyimpan sisa data TCP yang mungkin terpotong
    buffer = ""
    try:
        while True:
            data = conn.recv(1024)
            if not data:
                break
            
            buffer += data.decode('utf-8')
            
            # Memisahkan perintah jika ada beberapa perintah yang masuk bersamaan
            while '\n' in buffer:
                line, buffer = buffer.split('\n', 1)
                line = line.strip()
                if not line:
                    continue
                
                try:
                    command = json.loads(line)
                    execute_command(command)
                except json.JSONDecodeError:
                    print(f"[-] Data bukan JSON yang valid: {line}")
                except Exception as e:
                    print(f"[-] Gagal mengeksekusi perintah: {e}")

    except ConnectionResetError:
        print(f"[-] Koneksi terputus dari {addr}")
    finally:
        conn.close()
        print(f"[-] Klien {addr} terputus")

def execute_command(cmd):
    action_type = cmd.get("type")
    
    if action_type == "MOUSE_MOVE":
        dx = cmd.get("dx", 0)
        dy = cmd.get("dy", 0)
        # Pindahkan mouse relatif terhadap posisi sekarang
        pyautogui.moveRel(dx, dy)
        
    elif action_type == "MOUSE_CLICK":
        button = cmd.get("button", "left") # left, right, middle
        pyautogui.click(button=button)
        
    elif action_type == "TYPE_TEXT":
        text = cmd.get("text", "")
        if text:
            # interval = 0 berarti instan tanpa delay ketik
            pyautogui.write(text, interval=0.01)

def start_server():
    # Menonaktifkan fail-safe pyautogui (menggeser mouse ke pojok) agar tidak mudah crash
    pyautogui.FAILSAFE = False
    
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.bind((HOST, PORT))
    server.listen(5)
    print(f"[*] Server berjalan di {socket.gethostbyname(socket.gethostname())}:{PORT}")
    print("[*] Menunggu koneksi dari klien (Aplikasi Flutter)...")
    
    try:
        while True:
            conn, addr = server.accept()
            # Handle setiap client di thread berbeda
            client_thread = threading.Thread(target=handle_client, args=(conn, addr))
            client_thread.start()
    except KeyboardInterrupt:
        print("\n[*] Server dimatikan.")
    finally:
        server.close()

if __name__ == "__main__":
    start_server()
