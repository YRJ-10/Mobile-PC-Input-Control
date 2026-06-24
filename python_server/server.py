import socket
import json
import threading
import pyautogui
import soundcard as sc
import numpy as np
import tkinter as tk
from tkinter import font
import struct
import cv2
import mss

# Konfigurasi Port
HOST = '0.0.0.0'  
PORT = 8080
UDP_PORT = 8081
VIDEO_PORT = 8082

class PCMediaServerApp:
    def __init__(self, root):
        self.root = root
        self.root.title("PC Media Server")
        self.root.geometry("450x300")
        self.root.configure(bg="#1E1E2C")
        self.root.resizable(False, False)
        
        # Variabel State
        self.is_running = False
        self.server_socket = None
        self.server_thread = None
        self.audio_thread = None
        self.video_thread = None
        self.client_ip = None
        self.client_ip_lock = threading.Lock()
        self.audio_enabled = True
        
        self.setup_ui()
        
        # Audio Streamer (Berjalan terus di background, aktif saat klien konek)
        self.audio_thread = threading.Thread(target=self.audio_streamer, daemon=True)
        self.audio_thread.start()
        
    def setup_ui(self):
        # Header Judul
        lbl_title = tk.Label(self.root, text="Remote PC Server", font=("Segoe UI", 22, "bold"), bg="#1E1E2C", fg="#00E5FF")
        lbl_title.pack(pady=(25, 5))
        
        lbl_subtitle = tk.Label(self.root, text="Hubungkan HP Anda ke IP di bawah ini:", font=("Segoe UI", 11), bg="#1E1E2C", fg="#A0A0B5")
        lbl_subtitle.pack()
        
        # Kotak Tampilan IP Address (Mengambil IP Wi-Fi asli yang menghadap ke luar)
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            local_ip = s.getsockname()[0]
            s.close()
        except Exception:
            local_ip = "127.0.0.1"
            
        self.lbl_ip = tk.Label(self.root, text=f"{local_ip}", font=("Consolas", 24, "bold"), bg="#2B2B3C", fg="#00FF88", padx=20, pady=10)
        self.lbl_ip.pack(pady=15)
        
        # Teks Status Koneksi
        self.lbl_status = tk.Label(self.root, text="Status: Offline (Klik Start)", font=("Segoe UI", 11, "italic"), bg="#1E1E2C", fg="#FF4444")
        self.lbl_status.pack(pady=5)
        
        # Barisan Tombol
        self.btn_frame = tk.Frame(self.root, bg="#1E1E2C")
        self.btn_frame.pack(pady=10)
        
        self.btn_start = tk.Button(self.btn_frame, text="▶ START", font=("Segoe UI", 12, "bold"), bg="#00C853", fg="white", width=12, relief="flat", command=self.start_server)
        self.btn_start.grid(row=0, column=0, padx=10)
        
        self.btn_stop = tk.Button(self.btn_frame, text="■ STOP", font=("Segoe UI", 12, "bold"), bg="#D50000", fg="white", width=12, relief="flat", command=self.stop_server, state=tk.DISABLED)
        self.btn_stop.grid(row=0, column=1, padx=10)

    # Helper untuk update teks status dengan aman dari Thread berbeda
    def update_status(self, text, color="#FFFFFF"):
        def update():
            self.lbl_status.config(text=text, fg=color)
        self.root.after(0, update)

    def audio_streamer(self):
        udp_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            default_speaker = sc.default_speaker()
            mics = sc.all_microphones(include_loopback=True)
            loopback_mic = next((m for m in mics if m.isloopback and m.name == default_speaker.name), mics[0])
            
            with loopback_mic.recorder(samplerate=16000, channels=1) as mic:
                while True:
                    data = mic.record(numframes=256) # Low latency frame
                    data_int16 = (data * 32767).astype(np.int16)
                    
                    with self.client_ip_lock:
                        target_ip = self.client_ip
                    
                    # Hanya kirim suara jika server sedang berjalan, HP sudah terkoneksi, dan audio toggle dihidupkan
                    if target_ip and self.is_running and self.audio_enabled:
                        try:
                            udp_socket.sendto(data_int16.tobytes(), (target_ip, UDP_PORT))
                        except Exception:
                            pass
        except Exception as e:
            print(f"Audio Error: {e}")

    def execute_command(self, cmd):
        action_type = cmd.get("type")
        if action_type == "MOUSE_MOVE":
            pyautogui.moveRel(cmd.get("dx", 0), cmd.get("dy", 0))
        elif action_type == "MOUSE_CLICK":
            pyautogui.click(button=cmd.get("button", "left"))
        elif action_type == "TYPE_TEXT":
            text = cmd.get("text", "")
            if text:
                pyautogui.write(text, interval=0.01)
        elif action_type == "SCROLL":
            # Windows butuh angka yang besar untuk 1 'click' scroll (biasanya 120)
            # Kita kalikan dy dari Flutter dengan faktor pengali yang besar.
            dy = cmd.get("dy", 0)
            pyautogui.scroll(int(dy * 60)) # Arah dibalik menjadi positif
        elif action_type == "AUDIO_TOGGLE":
            self.audio_enabled = cmd.get("enabled", True)
        elif action_type == "SPECIAL_KEY":
            key = cmd.get("key", "")
            if key:
                if key == "copy":
                    pyautogui.hotkey('ctrl', 'c')
                elif key == "paste":
                    pyautogui.hotkey('ctrl', 'v')
                elif key == "alttab":
                    pyautogui.keyDown('alt')
                    pyautogui.press('tab')
                    pyautogui.keyUp('alt')
                elif key == "browserback":
                    pyautogui.hotkey('alt', 'left')
                elif key == "browserforward":
                    pyautogui.hotkey('alt', 'right')
                else:
                    pyautogui.press(key)
        elif action_type == "ZOOM":
            zoom_delta = cmd.get("delta", 0)
            if zoom_delta > 0:
                pyautogui.keyDown('ctrl')
                pyautogui.scroll(150)
                pyautogui.keyUp('ctrl')
            elif zoom_delta < 0:
                pyautogui.keyDown('ctrl')
                pyautogui.scroll(-150)
                pyautogui.keyUp('ctrl')
        elif action_type == "MEDIA":
            action = cmd.get("action", "")
            if action == "playpause":
                import ctypes
                VK_MEDIA_PLAY_PAUSE = 0xB3
                ctypes.windll.user32.keybd_event(VK_MEDIA_PLAY_PAUSE, 0, 0, 0) # Key Down
                ctypes.windll.user32.keybd_event(VK_MEDIA_PLAY_PAUSE, 0, 2, 0) # Key Up
        elif action_type in ["TOUCH_DOWN", "TOUCH_MOVE", "TOUCH_UP"]:
            screen_width, screen_height = pyautogui.size()
            x = int(cmd.get("rx", 0.5) * screen_width)
            y = int(cmd.get("ry", 0.5) * screen_height)
            pyautogui.moveTo(x, y)
            
            if action_type == "TOUCH_DOWN":
                pyautogui.mouseDown(button='left')
            elif action_type == "TOUCH_UP":
                pyautogui.mouseUp(button='left')

    def handle_client(self, conn, addr):
        self.update_status(f"HP Terhubung: {addr[0]}", "#00E5FF")
        with self.client_ip_lock:
            self.client_ip = addr[0]
            
        buffer = ""
        try:
            while self.is_running:
                data = conn.recv(1024)
                if not data:
                    break
                
                buffer += data.decode('utf-8')
                while '\n' in buffer:
                    line, buffer = buffer.split('\n', 1)
                    line = line.strip()
                    if not line: continue
                    try:
                        command = json.loads(line)
                        self.execute_command(command)
                    except Exception:
                        pass
        except Exception:
            pass
        finally:
            conn.close()
            with self.client_ip_lock:
                if self.client_ip == addr[0]:
                    self.client_ip = None
            if self.is_running:
                self.update_status("Status: Menunggu Koneksi HP...", "#FFD600")

    def video_stream_listener(self):
        video_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        video_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            video_socket.bind((HOST, VIDEO_PORT))
            video_socket.listen(5)
            video_socket.settimeout(1.0)
            
            while self.is_running:
                try:
                    conn, addr = video_socket.accept()
                except socket.timeout:
                    continue
                
                with mss.mss() as sct:
                    # Ambil monitor primer
                    monitor = sct.monitors[1]
                    while self.is_running:
                        try:
                            # Capture and compress
                            img = np.array(sct.grab(monitor))
                            frame = cv2.cvtColor(img, cv2.COLOR_BGRA2BGR)
                            frame = cv2.resize(frame, (1280, 720))
                            ret, jpeg = cv2.imencode('.jpg', frame, [int(cv2.IMWRITE_JPEG_QUALITY), 50])
                            
                            if not ret: continue
                            
                            data = jpeg.tobytes()
                            size_bytes = struct.pack("!I", len(data))
                            conn.sendall(size_bytes + data)
                        except Exception as e:
                            break
                conn.close()
        except Exception:
            pass
        finally:
            try:
                video_socket.close()
            except:
                pass

    def discovery_listener(self):
        udp_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        udp_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        udp_socket.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        try:
            udp_socket.bind(('', 8081))
            while self.is_running:
                data, addr = udp_socket.recvfrom(1024)
                message = data.decode('utf-8', errors='ignore').strip()
                if message == "DISCOVER_MOBILEPC":
                    udp_socket.sendto(b"MOBILEPC_SERVER", addr)
        except Exception:
            pass
        finally:
            udp_socket.close()

    def server_loop(self):
        try:
            self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.server_socket.bind((HOST, PORT))
            self.server_socket.listen(5)
            
            while self.is_running:
                try:
                    conn, addr = self.server_socket.accept()
                    client_thread = threading.Thread(target=self.handle_client, args=(conn, addr), daemon=True)
                    client_thread.start()
                except OSError:
                    break # Akan terjadi jika stop_server dipanggil (socket diclose)
        except Exception as e:
            self.update_status(f"Error: Port {PORT} mungkin terpakai", "#FF4444")
            self.stop_server()

    def start_server(self):
        if self.is_running: return
        self.is_running = True
        
        # Keamanan PyAutoGUI dan menghilangkan delay bawaan
        pyautogui.FAILSAFE = False
        pyautogui.PAUSE = 0
        
        self.btn_start.config(state=tk.DISABLED)
        self.btn_stop.config(state=tk.NORMAL)
        self.update_status("Status: Menunggu Koneksi HP...", "#FFD600")
        
        # Jalankan server jaringan di Thread agar tidak nge-hang
        self.network_thread = threading.Thread(target=self.server_loop, daemon=True)
        self.network_thread.start()
        
        # Jalankan UDP Discovery Listener
        self.discovery_thread = threading.Thread(target=self.discovery_listener, daemon=True)
        self.discovery_thread.start()
        
        # Jalankan Video Stream Listener
        self.video_thread = threading.Thread(target=self.video_stream_listener, daemon=True)
        self.video_thread.start()

    def stop_server(self):
        self.is_running = False
        if self.server_socket:
            try:
                self.server_socket.close()
            except:
                pass
            
        with self.client_ip_lock:
            self.client_ip = None
            
        self.btn_start.config(state=tk.NORMAL)
        self.btn_stop.config(state=tk.DISABLED)
        self.update_status("Status: Offline (Klik Start)", "#FF4444")

if __name__ == "__main__":
    root = tk.Tk()
    app = PCMediaServerApp(root)
    # Menangkap event tombol 'X' (Close)
    root.protocol("WM_DELETE_WINDOW", lambda: (app.stop_server(), root.destroy()))
    root.mainloop()
