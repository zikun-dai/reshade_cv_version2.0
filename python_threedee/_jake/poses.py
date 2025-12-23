import open3d as o3d
import numpy as np
import glob, os
import json

# ====== User configuration ======
DATA_DIR = r"C:\_Relax\Steam\steamapps\common\Crysis Remastered\Bin64\cv_saved\actions_2025-12-23_106405183"
# ================================

# hyperparameter
scale_factor = 100 # for better visualization
N_global = 100 # number of points for global XYZ
N_camera = 20 # number of points for camera xyz

# visualize the global XYZ
global_x = np.zeros((N_global, 3))
global_x[:,0] = np.linspace(0, 1, N_global)
global_x_color = np.zeros(global_x.shape)
global_x_color[:,0] = 1

global_y = np.zeros((N_global, 3))
global_y[:,1] = np.linspace(0, 1, N_global)
global_y_color = np.zeros(global_y.shape)
global_y_color[:,1] = 1

global_z = np.zeros((N_global, 3))
global_z[:,2] = np.linspace(0, 1, N_global)
global_z_color = np.zeros(global_z.shape)
global_z_color[:,2] = 1

# load camera's RT matrix
c2ws = []
frame_idxs = []
json_pattern = os.path.join(DATA_DIR, "*.json")
json_paths = sorted(glob.glob(json_pattern))

for json_path in json_paths:
    with open(json_path) as f:
        data = json.load(f)
    c2ws.append(np.asarray(data["extrinsic_cam2world"], dtype=np.float32).reshape(3, 4))
    frame_idxs.append(data.get("frame_idx"))
c2ws = np.array(c2ws)
print(c2ws.shape)
# c2ws[:, :3, 3] /= 100

# visualize the camera xyz
camera_centers = c2ws[:,:3,3] / scale_factor
camera_centers_color = np.zeros(camera_centers.shape)

axis_len = 0.1

camera_xs = np.linspace(0, axis_len, N_camera).reshape(N_camera, 1, 1)
camera_x_dirs = c2ws[:,:3,0]
camera_x_dirs = camera_x_dirs.reshape(1, *camera_x_dirs.shape)
camera_xs = camera_xs * camera_x_dirs + camera_centers[None]
camera_xs = camera_xs.reshape(-1, 3)
camera_xs_color = np.zeros(camera_xs.shape)
camera_xs_color[:,0] = 1

camera_ys = np.linspace(0, axis_len, N_camera).reshape(N_camera, 1, 1)
camera_y_dirs = c2ws[:,:3,1]
camera_y_dirs = camera_y_dirs.reshape(1, *camera_y_dirs.shape)
camera_ys = camera_ys * camera_y_dirs + camera_centers[None]
camera_ys = camera_ys.reshape(-1, 3)
camera_ys_color = np.zeros(camera_ys.shape)
camera_ys_color[:,1] = 1

camera_zs = np.linspace(0, axis_len, N_camera).reshape(N_camera, 1, 1)
camera_z_dirs = c2ws[:,:3,2]
camera_z_dirs = camera_z_dirs.reshape(1, *camera_z_dirs.shape)
camera_zs = camera_zs * camera_z_dirs + camera_centers[None]
camera_zs = camera_zs.reshape(-1, 3)
camera_zs_color = np.zeros(camera_zs.shape)
camera_zs_color[:,2] = 1

# plots
pts = np.concatenate([
    # camera_centers,
    # global_x, global_y, global_z, 
    camera_xs, camera_ys, 
    camera_zs,
], axis=0)
colors = np.concatenate([
    # camera_centers_color,
    # global_x_color, global_y_color, global_z_color, 
    camera_xs_color, camera_ys_color, 
    camera_zs_color,
], axis=0)

pcd = o3d.geometry.PointCloud()
pcd.points = o3d.utility.Vector3dVector(pts.reshape(-1,3))
pcd.colors = o3d.utility.Vector3dVector(colors.reshape(-1,3))

app = o3d.visualization.gui.Application.instance
app.initialize()

vis = o3d.visualization.O3DVisualizer()
vis.add_geometry("Points", pcd)
camera_x_ends = camera_centers + axis_len * c2ws[:, :3, 0]
camera_y_ends = camera_centers + axis_len * c2ws[:, :3, 1]
camera_z_ends = camera_centers + axis_len * c2ws[:, :3, 2]

add_label = vis.add_3d_label
for idx, frame_idx in enumerate(frame_idxs):
    label = str(frame_idx if frame_idx is not None else idx)
    add_label(camera_x_ends[idx], label)
    add_label(camera_y_ends[idx], label)
    add_label(camera_z_ends[idx], label)
vis.reset_camera_to_default()

app.add_window(vis)
app.run()
