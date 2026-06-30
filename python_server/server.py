import socket
import json
import threading
import pyautogui
import soundcard as sc
import numpy as np
import tkinter as tk
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
        self.root.title("MobilePC Server")
        self.root.geometry("560x460")
        self.root.configure(bg="#0F111A")
        self.root.resizable(False, False)
        self.colors = {
            "bg": "#0F111A",
            "panel": "#131520",
            "panel_alt": "#1A1D2D",
            "border": "#243044",
            "text": "#FFFFFF",
            "muted": "#8D94A6",
            "teal": "#64FFDA",
            "teal_dark": "#00796B",
            "green": "#69F0AE",
            "yellow": "#FFD600",
            "red": "#FF5252",
            "red_dark": "#2A1515",
            "blue": "#448AFF",
        }
        
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
        self.root.option_add("*Font", ("Segoe UI", 10))

        shell = tk.Frame(self.root, bg=self.colors["bg"], padx=24, pady=22)
        shell.pack(fill=tk.BOTH, expand=True)

        header = tk.Frame(shell, bg=self.colors["bg"])
        header.pack(fill=tk.X)

        title_group = tk.Frame(header, bg=self.colors["bg"])
        title_group.pack(side=tk.LEFT, anchor="w")

        tk.Label(
            title_group,
            text="MobilePC Server",
            font=("Segoe UI", 24, "bold"),
            bg=self.colors["bg"],
            fg=self.colors["text"],
        ).pack(anchor="w")

        tk.Label(
            title_group,
            text="Windows control bridge for your Android phone",
            font=("Segoe UI", 10),
            bg=self.colors["bg"],
            fg=self.colors["muted"],
        ).pack(anchor="w", pady=(2, 0))

        self.status_badge = tk.Label(
            header,
            text="OFFLINE",
            font=("Segoe UI", 10, "bold"),
            bg=self.colors["red_dark"],
            fg=self.colors["red"],
            padx=14,
            pady=7,
        )
        self.status_badge.pack(side=tk.RIGHT, anchor="ne", pady=4)

        self.local_ip = self.get_local_ip()

        ip_card = tk.Frame(
            shell,
            bg=self.colors["panel"],
            highlightbackground=self.colors["border"],
            highlightthickness=1,
            padx=20,
            pady=18,
        )
        ip_card.pack(fill=tk.X, pady=(26, 16))

        tk.Label(
            ip_card,
            text="PC IP ADDRESS",
            font=("Segoe UI", 9, "bold"),
            bg=self.colors["panel"],
            fg=self.colors["muted"],
        ).pack(anchor="w")

        ip_row = tk.Frame(ip_card, bg=self.colors["panel"])
        ip_row.pack(fill=tk.X, pady=(6, 0))

        self.lbl_ip = tk.Label(
            ip_row,
            text=self.local_ip,
            font=("Consolas", 28, "bold"),
            bg=self.colors["panel"],
            fg=self.colors["teal"],
        )
        self.lbl_ip.pack(side=tk.LEFT, anchor="w")

        self.btn_copy = self.make_button(
            ip_row,
            text="COPY IP",
            command=self.copy_ip,
            bg=self.colors["panel_alt"],
            fg=self.colors["teal"],
            active_bg="#20263A",
            width=10,
        )
        self.btn_copy.pack(side=tk.RIGHT, anchor="e", pady=4)

        self.btn_frame = tk.Frame(shell, bg=self.colors["bg"])
        self.btn_frame.pack(fill=tk.X, pady=(0, 16))

        self.btn_start = self.make_button(
            self.btn_frame,
            text="START SERVER",
            command=self.start_server,
            bg=self.colors["teal_dark"],
            fg="white",
            active_bg="#00897B",
            width=18,
            height=2,
        )
        self.btn_start.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=(0, 8))

        self.btn_stop = self.make_button(
            self.btn_frame,
            text="STOP SERVER",
            command=self.stop_server,
            bg=self.colors["red_dark"],
            fg=self.colors["red"],
            active_bg="#3A1D1D",
            width=18,
            height=2,
            state=tk.DISABLED,
        )
        self.btn_stop.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=(8, 0))

        status_card = tk.Frame(
            shell,
            bg=self.colors["panel_alt"],
            highlightbackground=self.colors["border"],
            highlightthickness=1,
            padx=18,
            pady=14,
        )
        status_card.pack(fill=tk.X, pady=(0, 16))

        tk.Label(
            status_card,
            text="Connection status",
            font=("Segoe UI", 10, "bold"),
            bg=self.colors["panel_alt"],
            fg=self.colors["text"],
        ).pack(anchor="w")

        self.lbl_status = tk.Label(
            status_card,
            text="Offline. Click Start to accept phone connection.",
            font=("Segoe UI", 10),
            bg=self.colors["panel_alt"],
            fg=self.colors["red"],
            wraplength=480,
            justify=tk.LEFT,
        )
        self.lbl_status.pack(anchor="w", pady=(4, 0))

        tk.Label(
            shell,
            text=f"Keep this window open while using the Android app. Ports: {PORT}, {UDP_PORT}, {VIDEO_PORT}.",
            font=("Segoe UI", 9),
            bg=self.colors["bg"],
            fg=self.colors["muted"],
        ).pack(anchor="w", pady=(2, 0))

    def get_local_ip(self):
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            local_ip = s.getsockname()[0]
            s.close()
            return local_ip
        except Exception:
            return "127.0.0.1"

    def make_button(self, parent, text, command, bg, fg, active_bg, width=12, height=1, state=tk.NORMAL):
        return tk.Button(
            parent,
            text=text,
            command=command,
            font=("Segoe UI", 10, "bold"),
            bg=bg,
            fg=fg,
            activebackground=active_bg,
            activeforeground=fg,
            disabledforeground="#5C6375",
            relief=tk.FLAT,
            borderwidth=0,
            width=width,
            height=height,
            cursor="hand2",
            state=state,
        )

    def copy_ip(self):
        self.root.clipboard_clear()
        self.root.clipboard_append(self.local_ip)
        self.update_status("IP address copied. Paste it in the Android app if auto-scan fails.", self.colors["teal"])

    # Helper untuk update teks status dengan aman dari Thread berbeda
    def update_status(self, text, color="#FFFFFF"):
        def update():
            self.lbl_status.config(text=text, fg=color)
            if color == self.colors["red"]:
                self.status_badge.config(text="OFFLINE", bg=self.colors["red_dark"], fg=self.colors["red"])
            elif color == self.colors["yellow"]:
                self.status_badge.config(text="WAITING", bg="#2E2A12", fg=self.colors["yellow"])
            elif color in (self.colors["teal"], "#00E5FF"):
                self.status_badge.config(text="CONNECTED", bg="#102C2D", fg=self.colors["teal"])
            else:
                self.status_badge.config(text="ONLINE", bg="#123020", fg=self.colors["green"])
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
        self.update_status(f"HP Terhubung: {addr[0]}", self.colors["teal"])
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
                self.update_status("Status: Menunggu Koneksi HP...", self.colors["yellow"])

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
            self.update_status(f"Error: Port {PORT} mungkin terpakai", self.colors["red"])
            self.stop_server()

    def start_server(self):
        if self.is_running: return
        self.is_running = True
        
        # Keamanan PyAutoGUI dan menghilangkan delay bawaan
        pyautogui.FAILSAFE = False
        pyautogui.PAUSE = 0
        
        self.btn_start.config(state=tk.DISABLED)
        self.btn_stop.config(state=tk.NORMAL)
        self.update_status("Status: Menunggu Koneksi HP...", self.colors["yellow"])
        
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
        self.update_status("Status: Offline (Klik Start)", self.colors["red"])

if __name__ == "__main__":
    root = tk.Tk()
    app = PCMediaServerApp(root)
    # Menangkap event tombol 'X' (Close)
    root.protocol("WM_DELETE_WINDOW", lambda: (app.stop_server(), root.destroy()))
    root.mainloop()
