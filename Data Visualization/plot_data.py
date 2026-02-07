import pandas as pd
import matplotlib.pyplot as plt

df = pd.read_csv("formfit_data2.csv")

fig, axs = plt.subplots(3, 1, figsize=(10, 8))

axs[0].plot(df["timestamp"], df["ax"], label="ax")
axs[0].plot(df["timestamp"], df["ay"], label="ay")
axs[0].plot(df["timestamp"], df["az"], label="az")
axs[0].set_title("Accelerometer")
axs[0].legend()

axs[1].plot(df["timestamp"], df["gx"], label="gx")
axs[1].plot(df["timestamp"], df["gy"], label="gy")
axs[1].plot(df["timestamp"], df["gz"], label="gz")
axs[1].set_title("Gyroscope")
axs[1].legend()

axs[2].plot(df["timestamp"], df["roll"], label="roll")
axs[2].plot(df["timestamp"], df["pitch"], label="pitch")
axs[2].plot(df["timestamp"], df["yaw"], label="yaw")
axs[2].set_title("Orientation")
axs[2].legend()

plt.tight_layout()
plt.show()
