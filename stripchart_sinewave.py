import numpy as np
import matplotlib.pyplot as plt
import matplotlib.animation as animation
from matplotlib.collections import LineCollection
from matplotlib import cm, colors
import sys, time, serial

plt.style.use('dark_background')


try:
    ser = serial.Serial(
        port='COM8',
        baudrate=115200,
        parity=serial.PARITY_NONE,
        stopbits=serial.STOPBITS_ONE,
        bytesize=serial.EIGHTBITS,
        timeout=0.1
    )
    print("Successfully opened COM8")
    time.sleep(2)
    ser.reset_input_buffer()
except Exception as e:
    print(f"ERROR: Could not open serial port: {e}")
    sys.exit(1)

xsize = 100
xdata, ydata = [], []

current_unit = None
min_temp = float('inf')
max_temp = float('-inf')

alpha = 0.2
smoothed_y = None

cmap_C = cm.get_cmap('viridis')
cmap_F = cm.get_cmap('plasma')

norm_C = colors.Normalize(vmin=0, vmax=50)     # Celsius range
norm_F = colors.Normalize(vmin=32, vmax=120)   # Fahrenheit range

def data_gen():
    t = 0
    while True:
        line = ser.readline()
        if not line:
            continue

        s = line.decode('utf-8', errors='ignore').strip()
        if not s:
            continue

        unit = 'F' if 'F' in s.upper() else 'C'
        numeric = ''.join(c for c in s if c.isdigit() or c == '.')
        try:
            val = float(numeric)
            yield t, val, unit
            t += 1
        except ValueError:
            continue

def run(data):
    global current_unit, min_temp, max_temp, smoothed_y
    t, y, unit = data

    if current_unit is not None and unit != current_unit:
        xdata.clear()
        ydata.clear()
        min_temp = float('inf')
        max_temp = float('-inf')
        smoothed_y = None

        if unit == 'C':
            line_collection.set_cmap(cmap_C)
            line_collection.set_norm(norm_C)
            cbar.set_label('Temperature (°C)')
        else:
            line_collection.set_cmap(cmap_F)
            line_collection.set_norm(norm_F)
            cbar.set_label('Temperature (°F)')

    current_unit = unit

    if smoothed_y is None:
        smoothed_y = y
    else:
        smoothed_y = alpha * y + (1 - alpha) * smoothed_y

    y_plot = smoothed_y

    min_temp = min(min_temp, y_plot)
    max_temp = max(max_temp, y_plot)

    xdata.append(t)
    ydata.append(y_plot)

    if len(xdata) > xsize:
        xdata.pop(0)
        ydata.pop(0)

    if len(xdata) > 1:
        points = np.array([xdata, ydata]).T.reshape(-1, 1, 2)
        segments = np.concatenate([points[:-1], points[1:]], axis=1)

        line_collection.set_segments(segments)
        line_collection.set_array(np.array(ydata))

    ax.set_xlim(xdata[0], xdata[-1] + 1)
    ax.set_ylim(min(ydata) - 2, max(ydata) + 2)

    ax.set_ylabel(f'Temperature (°{unit})')
    ax.set_title(
        f'Current: {y_plot:.1f}°{unit} | '
        f'Min: {min_temp:.1f}°{unit} | '
        f'Max: {max_temp:.1f}°{unit}',
        pad=-20
    )   

    return line_collection,

fig, ax = plt.subplots(figsize=(10, 6))
ax.margins(x=0.05, y=0.1)

line_collection = LineCollection(
    [], cmap=cmap_C, norm=norm_C, linewidth=2
)
ax.add_collection(line_collection)

cbar = plt.colorbar(line_collection, ax=ax)
cbar.set_label('Temperature (°C)')

ax.set_xlabel('Seconds (s)')
ax.grid(True, alpha=0.3)

ani = animation.FuncAnimation(
    fig, run, data_gen,
    interval=50,
    blit=False,
    cache_frame_data=False
)

plt.tight_layout()
plt.show()
ser.close()
