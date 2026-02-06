#!/usr/bin/env python3
"""
自动化数据处理流程（全自动版本）：
下载 → 解压 → 验证 → 处理 → 上传 → 清理
异常数据自动跳过，记录日志
"""
import os
import sys
import cv2
import glob
import shutil
import zipfile
import subprocess
import requests
import argparse
import json
import numpy as np
from pathlib import Path
from tqdm import tqdm
from math import ceil
from PIL import Image
from urllib.parse import urlparse, unquote
from datetime import datetime
from collections import defaultdict

# ==================== 配置参数 ====================
BASE_DIR = r"C:\Users\10762\Desktop\data\tmp"
OSS_BASE_PATH = "oss://antsys-robbyh20-b1/cyh/game_data_check/"
OSSUTIL_PATH = "ossutil"
GROUP_SIZE = 100

# 验证参数（零容忍模式）
VALIDATION_SAMPLE_RATE = 10  # 采样率：每N帧检查一次（提高速度）
DEPTH_ABNORMAL_MEAN_RANGE = (16400, 16600)  # 异常depth均值范围
DEPTH_ABNORMAL_STD_THRESHOLD = 10  # 异常depth标准差阈值
# 注意：不再使用ACCEPTABLE_ERROR_RATE，发现任何异常立即跳过action


# 日志文件
LOG_DIR = os.path.join(BASE_DIR, "logs")
os.makedirs(LOG_DIR, exist_ok=True)

# ==================== 日志模块 ====================
class ProcessLogger:
    """处理日志记录器"""
    
    def __init__(self, log_dir):
        self.log_dir = log_dir
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        self.log_file = os.path.join(log_dir, f"process_{timestamp}.log")
        self.error_file = os.path.join(log_dir, f"errors_{timestamp}.log")
        self.skipped_file = os.path.join(log_dir, f"skipped_{timestamp}.log")
        
        # 统计信息
        self.stats = {
            'total_urls': 0,
            'success': 0,
            'failed': 0,
            'skipped': 0,
            'actions_total': 0,
            'actions_skipped': 0,
            'actions_processed': 0
        }
    
    def log(self, message, level="INFO"):
        """记录日志"""
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        log_msg = f"[{timestamp}] [{level}] {message}"
        print(log_msg)
        
        with open(self.log_file, 'a', encoding='utf-8') as f:
            f.write(log_msg + "\n")
    
    def log_error(self, url_idx, url, error_msg):
        """记录错误"""
        self.log(f"URL [{url_idx}] 失败: {error_msg}", "ERROR")
        
        with open(self.error_file, 'a', encoding='utf-8') as f:
            f.write(f"[{url_idx}] {url}\n")
            f.write(f"错误: {error_msg}\n")
            f.write("-" * 60 + "\n")
    
    def log_skipped_action(self, action_name, reason, details):
        """记录跳过的action"""
        self.log(f"跳过 {action_name}: {reason}", "SKIP")
        
        with open(self.skipped_file, 'a', encoding='utf-8') as f:
            f.write(f"Action: {action_name}\n")
            f.write(f"原因: {reason}\n")
            f.write(f"详情: {details}\n")
            f.write("-" * 60 + "\n")
    
    def summary(self):
        """输出统计摘要"""
        self.log("\n" + "=" * 60, "SUMMARY")
        self.log("处理统计摘要", "SUMMARY")
        self.log("=" * 60, "SUMMARY")
        self.log(f"总URL数: {self.stats['total_urls']}", "SUMMARY")
        self.log(f"  成功: {self.stats['success']}", "SUMMARY")
        self.log(f"  失败: {self.stats['failed']}", "SUMMARY")
        self.log(f"  跳过: {self.stats['skipped']}", "SUMMARY")
        self.log(f"总Actions数: {self.stats['actions_total']}", "SUMMARY")
        self.log(f"  已处理: {self.stats['actions_processed']}", "SUMMARY")
        self.log(f"  已跳过: {self.stats['actions_skipped']}", "SUMMARY")
        self.log("=" * 60, "SUMMARY")

# 全局日志对象
logger = None

def find_camera_or_meta_file(action_dir, frame_idx):
    """
    查找camera或meta文件（兼容两种命名）
    优先级：camera.json > meta.json
    返回：文件路径或None
    """
    frame_prefix = f"frame_{frame_idx:06d}"
    
    # 优先查找camera.json
    camera_path = os.path.join(action_dir, f"{frame_prefix}_camera.json")
    if os.path.exists(camera_path):
        return camera_path
    
    # 如果没有camera.json，查找meta.json
    meta_path = os.path.join(action_dir, f"{frame_prefix}_meta.json")
    if os.path.exists(meta_path):
        return meta_path
    
    return None

def get_camera_meta_pattern():
    """返回camera/meta文件的glob模式"""
    return ["frame_*_camera.json", "frame_*_meta.json"]

# ==================== 数据验证模块 ====================
def check_depth_file(depth_path):
    """检查单个depth文件是否正常"""
    try:
        depth_data = np.load(depth_path)
        
        mean_val = np.mean(depth_data)
        std_val = np.std(depth_data)
        min_val = np.min(depth_data)
        max_val = np.max(depth_data)
        
        # 判断是否异常：均值在16499附近且标准差很小
        is_abnormal = (DEPTH_ABNORMAL_MEAN_RANGE[0] < mean_val < DEPTH_ABNORMAL_MEAN_RANGE[1] 
                      and std_val < DEPTH_ABNORMAL_STD_THRESHOLD)
        
        return {
            'valid': not is_abnormal,
            'mean': mean_val,
            'std': std_val,
            'min': min_val,
            'max': max_val
        }
    except Exception as e:
        return {
            'valid': False,
            'error': str(e)
        }

def check_camera_file(camera_path):
    """
    检查camera.json或meta.json文件是否正常
    两种文件内容相同，只是命名不同
    """
    try:
        with open(camera_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
        
        # 检查错误标记
        if 'cam_status' in data and data['cam_status'] == 'uninitialized':
            return {
                'valid': False,
                'reason': 'camera uninitialized',
                'file_type': 'camera/meta'
            }
        
        if 'err' in data:
            return {
                'valid': False,
                'reason': 'error in camera data',
                'error': data['err'],
                'file_type': 'camera/meta'
            }
        
        # 检查必需字段
        if 'extrinsic_cam2world' not in data:
            return {
                'valid': False,
                'reason': 'missing extrinsic_cam2world',
                'file_type': 'camera/meta'
            }
        
        return {
            'valid': True,
            'file_type': 'camera/meta'
        }
        
    except Exception as e:
        return {
            'valid': False,
            'reason': 'file read error',
            'error': str(e),
            'file_type': 'camera/meta'
        }


def validate_action_folder(action_dir, sample_rate=VALIDATION_SAMPLE_RATE):
    """
    验证action文件夹中的数据质量（兼容camera和meta）
    只要发现一个异常文件，立即返回不合格
    采用采样检查以提高速度
    """
    action_name = os.path.basename(action_dir)
    
    # 查找所有depth文件
    depth_files = sorted(glob.glob(os.path.join(action_dir, "frame_*_depth.npy")))
    total_frames = len(depth_files)
    
    if total_frames == 0:
        return {
            'valid': False,
            'action_name': action_name,
            'reason': 'no_frames',
            'message': '未找到帧文件',
            'first_error_frame': None
        }
    
    # 检测使用的是camera还是meta命名
    camera_files = glob.glob(os.path.join(action_dir, "frame_*_camera.json"))
    meta_files = glob.glob(os.path.join(action_dir, "frame_*_meta.json"))
    
    if camera_files:
        file_type = "camera.json"
    elif meta_files:
        file_type = "meta.json"
    else:
        return {
            'valid': False,
            'action_name': action_name,
            'reason': 'no_camera_meta',
            'message': '未找到camera.json或meta.json文件',
            'first_error_frame': None
        }
    
    logger.log(f"   检测到文件类型: {file_type}")
    
    checked_count = 0
    
    # 采样检查（一旦发现异常立即返回）
    for i in range(0, total_frames, sample_rate):
        frame_idx = i
        depth_path = os.path.join(action_dir, f"frame_{frame_idx:06d}_depth.npy")
        camera_meta_path = find_camera_or_meta_file(action_dir, frame_idx)
        
        # 检查depth
        if os.path.exists(depth_path):
            depth_result = check_depth_file(depth_path)
            if not depth_result['valid']:
                # 发现异常，立即返回
                error_detail = depth_result.get('error', 
                    f"mean={depth_result.get('mean', 0):.1f}, std={depth_result.get('std', 0):.1f}")
                return {
                    'valid': False,
                    'action_name': action_name,
                    'reason': 'depth_abnormal',
                    'message': f'发现depth异常文件',
                    'first_error_frame': frame_idx,
                    'error_type': 'depth',
                    'error_detail': error_detail,
                    'total_frames': total_frames,
                    'checked_frames': checked_count + 1
                }
        
        # 检查camera/meta
        if camera_meta_path:
            camera_result = check_camera_file(camera_meta_path)
            if not camera_result['valid']:
                # 发现异常，立即返回
                return {
                    'valid': False,
                    'action_name': action_name,
                    'reason': 'camera_meta_abnormal',
                    'message': f'发现{file_type}异常文件',
                    'first_error_frame': frame_idx,
                    'error_type': file_type,
                    'error_detail': camera_result.get('reason', 'unknown') + 
                                   (f": {camera_result.get('error', '')}" if 'error' in camera_result else ''),
                    'total_frames': total_frames,
                    'checked_frames': checked_count + 1
                }
        else:
            # 缺失camera/meta文件
            return {
                'valid': False,
                'action_name': action_name,
                'reason': 'missing_camera_meta',
                'message': f'缺失{file_type}文件',
                'first_error_frame': frame_idx,
                'error_type': file_type,
                'error_detail': '文件不存在',
                'total_frames': total_frames,
                'checked_frames': checked_count + 1
            }
        
        checked_count += 1
    
    # 全部检查通过
    return {
        'valid': True,
        'action_name': action_name,
        'total_frames': total_frames,
        'checked_frames': checked_count,
        'file_type': file_type,
        'message': '数据质量正常'
    }


# ==================== 下载模块 ====================
def download_file(url, save_path):
    """下载文件"""
    logger.log(f"开始下载: {os.path.basename(save_path)}")
    
    try:
        if os.path.exists(save_path):
            logger.log(f"文件已存在，跳过下载")
            return True
        
        response = requests.get(url, stream=True, timeout=30)
        response.raise_for_status()
        
        total_size = int(response.headers.get('content-length', 0))
        
        with open(save_path, 'wb') as f, tqdm(
            desc=os.path.basename(save_path),
            total=total_size,
            unit='B',
            unit_scale=True,
            unit_divisor=1024,
        ) as pbar:
            for chunk in response.iter_content(chunk_size=8192):
                if chunk:
                    f.write(chunk)
                    pbar.update(len(chunk))
        
        logger.log(f"下载完成: {os.path.basename(save_path)}")
        return True
        
    except Exception as e:
        logger.log(f"下载失败: {str(e)}", "ERROR")
        if os.path.exists(save_path):
            os.remove(save_path)
        return False

def extract_filename_from_url(url):
    """从URL提取文件名"""
    parsed = urlparse(url)
    filename = os.path.basename(parsed.path)
    filename = unquote(filename)
    return filename

# ==================== 解压模块 ====================
def normalize_folder_structure(folder_path):
    """自动标准化文件夹结构（处理嵌套）"""
    max_iterations = 3
    iteration = 0
    
    while iteration < max_iterations:
        iteration += 1
        items = os.listdir(folder_path)
        
        # 检查是否已正常
        has_actions = any(item.startswith('actions_') for item in items 
                         if os.path.isdir(os.path.join(folder_path, item)))
        has_groups = any(item.startswith('group_') for item in items 
                        if os.path.isdir(os.path.join(folder_path, item)))
        
        if has_actions or has_groups:
            return True
        
        # 如果只有一个文件夹，尝试提升
        folders = [item for item in items if os.path.isdir(os.path.join(folder_path, item))]
        
        if len(folders) == 1:
            single_folder = folders[0]
            single_folder_path = os.path.join(folder_path, single_folder)
            
            logger.log(f"检测到嵌套文件夹，提升层级: {single_folder}")
            
            sub_items = os.listdir(single_folder_path)
            
            for item in sub_items:
                src = os.path.join(single_folder_path, item)
                dst = os.path.join(folder_path, item)
                
                if os.path.exists(dst):
                    continue
                
                try:
                    shutil.move(src, dst)
                except Exception as e:
                    logger.log(f"移动失败 {item}: {str(e)}", "ERROR")
            
            # 删除空文件夹
            try:
                if not os.listdir(single_folder_path):
                    os.rmdir(single_folder_path)
            except:
                pass
            
            continue
        else:
            break
    
    # 最终检查
    final_items = os.listdir(folder_path)
    has_actions = any(item.startswith('actions_') for item in final_items 
                     if os.path.isdir(os.path.join(folder_path, item)))
    has_groups = any(item.startswith('group_') for item in final_items 
                    if os.path.isdir(os.path.join(folder_path, item)))
    
    return has_actions or has_groups

def extract_zip(zip_path, extract_to):
    """解压ZIP并标准化结构"""
    logger.log(f"开始解压: {os.path.basename(zip_path)}")
    
    try:
        zip_basename = os.path.splitext(os.path.basename(zip_path))[0]
        target_folder = os.path.join(extract_to, zip_basename)
        
        os.makedirs(target_folder, exist_ok=True)
        
        with zipfile.ZipFile(zip_path, 'r') as zip_ref:
            zip_ref.extractall(target_folder)
        
        logger.log(f"解压完成，标准化结构中...")
        
        # 标准化结构
        normalize_folder_structure(target_folder)
        
        # 删除ZIP
        try:
            os.remove(zip_path)
            logger.log("已删除ZIP文件")
        except Exception as e:
            logger.log(f"删除ZIP失败: {str(e)}", "WARN")
        return target_folder
        
    except Exception as e:
        logger.log(f"解压失败: {str(e)}", "ERROR")
        return None

# ==================== 数据处理模块 ====================
def extract_rgb_from_video(video_path, output_dir):
    """提取RGB帧"""
    os.makedirs(output_dir, exist_ok=True)
    cap = cv2.VideoCapture(video_path)
    
    if not cap.isOpened():
        logger.log(f"无法打开视频: {video_path}", "ERROR")
        return 0
    
    total_video_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    logger.log(f"提取视频帧: {os.path.basename(video_path)} (共{total_video_frames}帧)")
    
    for frame_idx in tqdm(range(total_video_frames), desc="提取RGB帧"):
        ret, bgr = cap.read()
        if not ret:
            continue
        rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
        img = Image.fromarray(rgb)
        png_filename = os.path.join(output_dir, f"frame_{frame_idx:06d}_RGB.png")
        img.save(png_filename, format='PNG')
    
    cap.release()
    logger.log(f"RGB帧提取完成")
    return total_video_frames

def split_frames_to_groups(action_dir, total_frames, group_size=GROUP_SIZE):
    """生成group（兼容camera和meta）"""
    total_groups = ceil(total_frames / group_size)
    logger.log(f"分组: {total_frames}帧 → {total_groups}组")
    
    action_basename = os.path.basename(action_dir)
    action_unique_id = action_basename.replace("actions_", "")
    group_info_list = []
    
    # 检测使用的文件类型
    has_camera = os.path.exists(os.path.join(action_dir, "frame_000000_camera.json"))
    has_meta = os.path.exists(os.path.join(action_dir, "frame_000000_meta.json"))
    
    for group_idx in tqdm(range(total_groups), desc="生成group"):
        start_frame = group_idx * group_size
        end_frame = min((group_idx + 1) * group_size - 1, total_frames - 1)
        group_unique_name = f"group_{action_unique_id}_{group_idx + 1:03d}"
        temp_group_path = os.path.join(action_dir, group_unique_name)
        os.makedirs(temp_group_path, exist_ok=True)
        
        for frame_idx in range(start_frame, end_frame + 1):
            frame_prefix = f"frame_{frame_idx:06d}"
            
            # 基础文件
            files_to_copy = [
                f"{frame_prefix}_RGB.png",
                f"{frame_prefix}_depth.npy"
            ]
            
            # 添加camera或meta文件
            if has_camera:
                files_to_copy.append(f"{frame_prefix}_camera.json")
            if has_meta:
                files_to_copy.append(f"{frame_prefix}_meta.json")
            
            # 复制文件
            for filename in files_to_copy:
                src = os.path.join(action_dir, filename)
                dst = os.path.join(temp_group_path, filename)
                if os.path.exists(src):
                    shutil.copy2(src, dst)
        
        group_info_list.append((temp_group_path, group_unique_name))
    
    logger.log(f"分组完成: {len(group_info_list)}个group")
    return group_info_list

def move_single_action_groups(group_info_list, root_dir, action_dir):
    """移动group到根目录"""
    success_count = 0
    all_moved = True
    
    for temp_group_path, group_unique_name in tqdm(group_info_list, desc="移动group"):
        target_group_path = os.path.join(root_dir, group_unique_name)
        
        try:
            if os.path.exists(target_group_path):
                all_moved = False
                continue
            
            shutil.move(temp_group_path, target_group_path)
            if os.path.exists(target_group_path):
                success_count += 1
            else:
                all_moved = False
        except Exception as e:
            logger.log(f"移动group失败: {str(e)}", "ERROR")
            all_moved = False
    
    logger.log(f"group移动完成: {success_count}个成功")
    return all_moved

def delete_action_folder(action_dir):
    """删除action文件夹"""
    try:
        shutil.rmtree(action_dir)
        if not os.path.exists(action_dir):
            return True
        return False
    except Exception as e:
        logger.log(f"删除action文件夹失败: {str(e)}", "ERROR")
        return False

def process_single_action(action_dir, root_dir):
    """
    处理单个action（兼容camera和meta，零容忍）
    返回: True=成功, False=失败, None=跳过（数据质量问题）
    """
    action_name = os.path.basename(action_dir)
    logger.log(f"处理action: {action_name}")
    
    # 步骤1: 验证数据质量（零容忍）
    logger.log(f"验证数据质量（采样率: 每{VALIDATION_SAMPLE_RATE}帧）...")
    validation_result = validate_action_folder(action_dir)
    
    if not validation_result['valid']:
        # 发现异常文件，自动跳过整个action
        error_frame = validation_result.get('first_error_frame')
        error_type = validation_result.get('error_type', 'unknown')
        error_detail = validation_result.get('error_detail', '')
        
        skip_message = (
            f"发现异常文件，跳过整个action\n"
            f"      总帧数: {validation_result.get('total_frames', 0)}\n"
            f"      已检查: {validation_result.get('checked_frames', 0)} 帧\n"
            f"      异常帧: frame_{error_frame:06d} (如果有)\n"
            f"      异常类型: {error_type}\n"
            f"      详细信息: {error_detail}"
        )
        
        logger.log(f"❌ {skip_message}", "SKIP")
        logger.log_skipped_action(
            action_name,
            validation_result.get('reason', 'unknown'),
            skip_message
        )
        logger.stats['actions_skipped'] += 1
        return None  # 返回None表示跳过
    
    file_type = validation_result.get('file_type', 'camera.json')
    logger.log(f"✅ 数据质量验证通过（检查了{validation_result['checked_frames']}帧，文件类型: {file_type}）")
    
    # 步骤2: 检查视频文件
    video_path = os.path.join(action_dir, "capture.mp4")
    if not os.path.exists(video_path):
        logger.log(f"未找到capture.mp4", "WARN")
        return False
    
    # 步骤3: 提取RGB帧
    total_frames = extract_rgb_from_video(video_path, action_dir)
    if total_frames == 0:
        logger.log(f"视频帧提取失败", "ERROR")
        return False
    
    # 步骤4: 生成group
    group_info_list = split_frames_to_groups(action_dir, total_frames)
    
    # 步骤5: 删除原始数据（兼容camera和meta）
    logger.log(f"删除原始数据...")
    if os.path.exists(video_path):
        os.remove(video_path)
    
    # 检测文件类型
    has_camera = os.path.exists(os.path.join(action_dir, "frame_000000_camera.json"))
    has_meta = os.path.exists(os.path.join(action_dir, "frame_000000_meta.json"))
    
    for frame_idx in range(total_frames):
        frame_prefix = f"frame_{frame_idx:06d}"
        files_to_delete = [
            f"{frame_prefix}_RGB.png",
            f"{frame_prefix}_depth.npy"
        ]
        
        # 添加camera或meta文件
        if has_camera:
            files_to_delete.append(f"{frame_prefix}_camera.json")
        if has_meta:
            files_to_delete.append(f"{frame_prefix}_meta.json")
        
        for filename in files_to_delete:
            file_path = os.path.join(action_dir, filename)
            if os.path.exists(file_path):
                try:
                    os.remove(file_path)
                except:
                    pass
    
    # 步骤6: 移动group
    all_groups_moved = move_single_action_groups(group_info_list, root_dir, action_dir)
    
    # 步骤7: 删除action文件夹
    if all_groups_moved:
        delete_action_folder(action_dir)
    
    logger.stats['actions_processed'] += 1
    return True

def process_extracted_folder(folder_path):
    """
    处理解压后的文件夹（全自动，零容忍）
    """
    logger.log(f"处理文件夹: {os.path.basename(folder_path)}")
    
    # 查找所有actions
    action_dirs = sorted(glob.glob(os.path.join(folder_path, "actions_*")))
    
    if not action_dirs:
        # 检查是否已经是group格式
        group_dirs = glob.glob(os.path.join(folder_path, "group_*"))
        if group_dirs:
            logger.log(f"发现{len(group_dirs)}个group，数据已处理好")
            return True
        
        logger.log(f"未找到actions或group文件夹", "WARN")
        return False
    
    logger.log(f"找到{len(action_dirs)}个actions")
    logger.stats['actions_total'] += len(action_dirs)
    
    success_count = 0
    skipped_count = 0
    failed_count = 0
    
    for action_dir in action_dirs:
        logger.log(f"\n{'─'*60}")
        result = process_single_action(action_dir, folder_path)
        
        if result is True:
            success_count += 1
            logger.log(f"✅ Action处理成功: {os.path.basename(action_dir)}")
        elif result is None:
            skipped_count += 1
            logger.log(f"⏭️ Action已跳过: {os.path.basename(action_dir)}")
        else:
            failed_count += 1
            logger.log(f"❌ Action处理失败: {os.path.basename(action_dir)}")
    
    logger.log(f"\n{'─'*60}")
    logger.log(f"文件夹处理汇总:")
    logger.log(f"  ✅ 成功: {success_count}/{len(action_dirs)}")
    logger.log(f"  ⏭️ 跳过: {skipped_count}/{len(action_dirs)}")
    logger.log(f"  ❌ 失败: {failed_count}/{len(action_dirs)}")
    logger.log(f"{'─'*60}")
    
    # 只要有成功的就算成功
    return success_count > 0

# ==================== OSS上传模块 ====================
def get_game_name_from_folder(folder_name):
    """提取游戏名称"""
    game_name = folder_name.split('-')[0]
    return game_name

def upload_tmp_to_oss(tmp_path, oss_base_path):
    """上传tmp到OSS"""
    logger.log("开始上传到OSS")
    
    subfolders = [f for f in os.listdir(tmp_path) 
                  if os.path.isdir(os.path.join(tmp_path, f)) and f != 'logs']
    
    if not subfolders:
        logger.log("tmp文件夹为空", "WARN")
        return True
    
    first_folder = subfolders[0]
    game_name = get_game_name_from_folder(first_folder)
    oss_target_path = f"{oss_base_path}{game_name}/"
    
    logger.log(f"本地: {tmp_path}")
    logger.log(f"OSS: {oss_target_path}")
    logger.log(f"游戏: {game_name}")
    
    # 统计文件
    total_files = 0
    total_size = 0
    for folder in subfolders:
        folder_path = os.path.join(tmp_path, folder)
        for root, dirs, files in os.walk(folder_path):
            total_files += len(files)
            for file in files:
                try:
                    total_size += os.path.getsize(os.path.join(root, file))
                except:
                    pass
    
    logger.log(f"文件数: {total_files:,}, 大小: {total_size / (1024**3):.2f} GB")
    
    try:
        cmd = [
            OSSUTIL_PATH,
            'cp',
            '-r',
            '-u',
            '--jobs', '3',
            tmp_path,
            oss_target_path
        ]
        
        logger.log(f"执行上传命令...")
        
        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding='utf-8',
            errors='ignore',
            bufsize=1
        )
        
        for line in process.stdout:
            line = line.strip()
            if line:
                print(f"   {line}")
        
        return_code = process.wait()
        
        if return_code == 0:
            logger.log("上传成功")
            return True
        else:
            logger.log(f"上传失败，返回码: {return_code}", "ERROR")
            return False
            
    except FileNotFoundError:
        logger.log(f"找不到ossutil: {OSSUTIL_PATH}", "ERROR")
        return False
    except Exception as e:
        logger.log(f"上传出错: {str(e)}", "ERROR")
        return False

# ==================== 清理模块 ====================
def cleanup_tmp_folder(tmp_path):
    """清空tmp（保留logs）"""
    logger.log("清理tmp文件夹")
    
    try:
        for item in os.listdir(tmp_path):
            if item == 'logs':  # 保留日志文件夹
                continue
            
            item_path = os.path.join(tmp_path, item)
            
            if os.path.isdir(item_path):
                shutil.rmtree(item_path)
            else:
                os.remove(item_path)
        
        remaining = [f for f in os.listdir(tmp_path) if f != 'logs']
        if not remaining:
            logger.log("tmp已清空")
            return True
        else:
            logger.log(f"仍有{len(remaining)}个项目未删除", "WARN")
            return False
            
    except Exception as e:
        logger.log(f"清理出错: {str(e)}", "ERROR")
        return False

# ==================== 主流程 ====================
def process_single_url(url, tmp_dir, oss_base_path):
    """处理单个URL（全自动）"""
    logger.log("\n" + "#" * 60)
    logger.log("开始处理新的数据包")
    logger.log("#" * 60)
    
    # 下载
    filename = extract_filename_from_url(url)
    zip_path = os.path.join(tmp_dir, filename)
    
    if not download_file(url, zip_path):
        return False
    
    # 解压
    extracted_folder = extract_zip(zip_path, tmp_dir)
    if not extracted_folder or not os.path.exists(extracted_folder):
        return False
    
    # 处理（自动验证和跳过异常）
    try:
        process_result = process_extracted_folder(extracted_folder)
        if not process_result:
            logger.log("处理失败或全部跳过", "WARN")
            # 自动清理失败的数据
            cleanup_tmp_folder(tmp_dir)
            return False
    except Exception as e:
        logger.log(f"处理出错: {str(e)}", "ERROR")
        import traceback
        traceback.print_exc()
        cleanup_tmp_folder(tmp_dir)
        return False
    
    # 上传
    if not upload_tmp_to_oss(tmp_dir, oss_base_path):
        logger.log("上传失败，保留本地文件", "ERROR")
        return False
    
    # 清理
    cleanup_tmp_folder(tmp_dir)
    
    logger.log("#" * 60)
    logger.log("数据包处理完成")
    logger.log("#" * 60 + "\n")
    
    return True

def main():
    parser = argparse.ArgumentParser(
        description="自动化数据处理流程（零容忍版本）：发现异常立即跳过action",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
使用示例：
  python script.py urls.txt
  python script.py urls.txt --start-from 5
  python script.py urls.txt --sample-rate 20  # 加快验证速度
  
特性：
  - 全自动处理，无需人工干预
  - 零容忍策略：发现任何异常文件立即跳过整个action
  - 采样验证：每N帧检查一次，提高处理速度
  - 异常action不上传，但会继续处理其他action
  - 详细日志记录所有跳过的action
        """
    )
    parser.add_argument(
        "url_file",
        help="包含下载链接的文本文件路径"
    )
    parser.add_argument(
        "--start-from",
        type=int,
        default=1,
        help="从第几个URL开始处理（默认从第1个开始）"
    )
    parser.add_argument(
        "--skip-upload",
        action="store_true",
        help="跳过上传步骤（测试模式）"
    )
    parser.add_argument(
        "--sample-rate",
        type=int,
        default=10,  # 直接使用数值，不引用全局变量
        help=f"验证采样率：每N帧检查一次（默认10）"
    )
    
    args = parser.parse_args()
    
    # 先声明全局变量，再修改
    global logger, VALIDATION_SAMPLE_RATE
    
    # 初始化日志
    logger = ProcessLogger(LOG_DIR)
    
    # 更新全局配置
    VALIDATION_SAMPLE_RATE = args.sample_rate
    
    # 读取URL列表
    if not os.path.exists(args.url_file):
        print(f"❌ URL文件不存在: {args.url_file}")
        return
    
    try:
        with open(args.url_file, 'r', encoding='utf-8') as f:
            urls = [line.strip() for line in f if line.strip() and not line.startswith('#')]
    except Exception as e:
        print(f"❌ 读取URL文件失败: {str(e)}")
        return
    
    if not urls:
        print(f"❌ URL文件为空")
        return
    
    # 创建目录
    os.makedirs(BASE_DIR, exist_ok=True)
    
    # 显示配置
    logger.log("="*60)
    logger.log("自动化数据处理流程（零容忍版本）")
    logger.log("="*60)
    logger.log(f"工作目录: {BASE_DIR}")
    logger.log(f"OSS路径: {OSS_BASE_PATH}")
    logger.log(f"总URL数: {len(urls)}")
    logger.log(f"开始位置: 第{args.start_from}个")
    logger.log(f"验证采样率: 每{VALIDATION_SAMPLE_RATE}帧")
    logger.log(f"验证策略: 零容忍（发现任何异常立即跳过action）")
    logger.log(f"日志目录: {LOG_DIR}")
    if args.skip_upload:
        logger.log("⚠️ 测试模式：跳过上传")
    logger.log("="*60)
    
    # 统计
    logger.stats['total_urls'] = len(urls)
    failed_urls = []
    
    # 开始处理
    try:
        for idx, url in enumerate(urls, 1):
            if idx < args.start_from:
                logger.log(f"⏭️ 跳过第{idx}个URL")
                continue
            
            logger.log(f"\n{'='*60}")
            logger.log(f"[总进度: {idx}/{len(urls)}] 处理第{idx}个URL")
            logger.log(f"{'='*60}")
            
            filename = extract_filename_from_url(url)
            logger.log(f"文件: {filename}")
            
            try:
                if args.skip_upload:
                    # 测试模式
                    zip_path = os.path.join(BASE_DIR, filename)
                    if download_file(url, zip_path):
                        extracted_folder = extract_zip(zip_path, BASE_DIR)
                        if extracted_folder:
                            if process_extracted_folder(extracted_folder):
                                logger.stats['success'] += 1
                                logger.log(f"✅ 第{idx}个URL处理成功（测试模式）")
                            else:
                                logger.stats['failed'] += 1
                                failed_urls.append((idx, url))
                        else:
                            logger.stats['failed'] += 1
                            failed_urls.append((idx, url))
                    else:
                        logger.stats['failed'] += 1
                        failed_urls.append((idx, url))
                else:
                    # 正常模式
                    if process_single_url(url, BASE_DIR, OSS_BASE_PATH):
                        logger.stats['success'] += 1
                        logger.log(f"✅ 第{idx}个URL处理成功")
                    else:
                        logger.stats['failed'] += 1
                        failed_urls.append((idx, url))
                        logger.log_error(idx, url, "处理流程失败")
                
            except KeyboardInterrupt:
                raise
            except Exception as e:
                logger.stats['failed'] += 1
                failed_urls.append((idx, url))
                logger.log_error(idx, url, str(e))
                import traceback
                traceback.print_exc()
            
            # 当前进度
            logger.log(f"\n📊 当前进度: "
                      f"成功{logger.stats['success']}个, "
                      f"失败{logger.stats['failed']}个, "
                      f"剩余{len(urls) - idx}个")
    
    except KeyboardInterrupt:
        logger.log("\n⚠️ 用户中断操作", "WARN")
        logger.log(f"已处理: {idx - 1}/{len(urls)}")
    
    # 最终统计
    logger.summary()
    
    if failed_urls:
        logger.log(f"\n❌ 失败的URL列表:")
        for idx, url in failed_urls:
            filename = extract_filename_from_url(url)
            logger.log(f"   [{idx}] {filename}")
        
        # 保存失败列表
        failed_file = os.path.join(LOG_DIR, "failed_urls.txt")
        try:
            with open(failed_file, 'w', encoding='utf-8') as f:
                for idx, url in failed_urls:
                    f.write(f"{url}\n")
            logger.log(f"\n💾 失败URL已保存到: {failed_file}")
        except Exception as e:
            logger.log(f"保存失败列表出错: {str(e)}", "ERROR")
    
    logger.log(f"\n📁 日志文件:")
    logger.log(f"   完整日志: {logger.log_file}")
    logger.log(f"   错误日志: {logger.error_file}")
    logger.log(f"   跳过记录: {logger.skipped_file}")


if __name__ == '__main__':
    main()
