#!/usr/bin/env python3
"""
自动化数据处理流程（串行版本）：
逐个处理：下载 → 解压 → 处理 → 上传OSS → 清理 → 下一个
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
from pathlib import Path
from tqdm import tqdm
from math import ceil
from PIL import Image
from urllib.parse import urlparse, unquote

# ==================== 配置参数 ====================
BASE_DIR = r"C:\Users\10762\Desktop\data\tmp"
OSS_BASE_PATH = "oss://antsys-robbyh20-b1/cyh/game_data/"  # 根据实际情况修改
OSSUTIL_PATH = "ossutil"  # 如果ossutil不在PATH中，请修改为完整路径
GROUP_SIZE = 100  # 每组帧数

# ==================== 下载模块 ====================
def download_file(url, save_path):
    """下载单个文件，支持断点续传"""
    print(f"\n📥 开始下载: {os.path.basename(save_path)}")
    
    try:
        # 检查文件是否已存在
        if os.path.exists(save_path):
            existing_size = os.path.getsize(save_path)
            print(f"   ⚠️ 文件已存在，大小: {existing_size / (1024**2):.2f}MB")
            confirm = input(f"   是否重新下载？(y/n): ")
            if confirm.lower() != 'y':
                print(f"   ✅ 使用已存在文件")
                return True
            os.remove(save_path)
        
        # 发起下载请求
        response = requests.get(url, stream=True, timeout=30)
        response.raise_for_status()
        
        total_size = int(response.headers.get('content-length', 0))
        
        # 使用进度条下载
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
        
        print(f"✅ 下载完成: {os.path.basename(save_path)}")
        return True
        
    except Exception as e:
        print(f"❌ 下载失败: {str(e)}")
        if os.path.exists(save_path):
            os.remove(save_path)
        return False

def extract_filename_from_url(url):
    """从URL中提取文件名（处理URL编码）"""
    parsed = urlparse(url)
    filename = os.path.basename(parsed.path)
    filename = unquote(filename)
    return filename

# ==================== 解压模块 ====================
def extract_zip(zip_path, extract_to):
    """
    解压ZIP文件到指定文件夹
    确保解压后的结构为：extract_to/压缩包名（不含.zip）/actions_xxx/
    """
    print(f"\n📦 开始解压: {os.path.basename(zip_path)}")
    
    try:
        # 获取压缩包名称（不含.zip）
        zip_basename = os.path.splitext(os.path.basename(zip_path))[0]
        target_folder = os.path.join(extract_to, zip_basename)
        
        # 创建目标文件夹
        os.makedirs(target_folder, exist_ok=True)
        
        with zipfile.ZipFile(zip_path, 'r') as zip_ref:
            # 解压到目标文件夹
            zip_ref.extractall(target_folder)
        
        print(f"✅ 解压完成: {zip_basename}")
        print(f"   解压路径: {target_folder}")
        
        # 删除ZIP文件以节省空间
        try:
            os.remove(zip_path)
            print(f"🗑️ 已删除ZIP文件")
        except Exception as e:
            print(f"⚠️ 删除ZIP失败: {str(e)}")
        
        return target_folder
        
    except Exception as e:
        print(f"❌ 解压失败: {str(e)}")
        return None

# ==================== 数据处理模块 ====================
def extract_rgb_from_video(video_path, output_dir):
    """提取RGB帧"""
    os.makedirs(output_dir, exist_ok=True)
    cap = cv2.VideoCapture(video_path)
    
    if not cap.isOpened():
        print(f"❌ 无法打开视频文件: {video_path}")
        return 0
    
    total_video_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    
    print(f"🎥 正在提取视频帧: {os.path.basename(video_path)} (共{total_video_frames}帧)")
    
    for frame_idx in tqdm(range(total_video_frames), desc="提取RGB帧"):
        ret, bgr = cap.read()
        if not ret:
            print(f"⚠️ 跳过第{frame_idx}帧（读取失败）")
            continue
        rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
        img = Image.fromarray(rgb)
        png_filename = os.path.join(output_dir, f"frame_{frame_idx:06d}_RGB.png")
        img.save(png_filename, format='PNG')
    
    cap.release()
    print(f"✅ RGB帧提取完成，共{total_video_frames}帧")
    return total_video_frames

def split_frames_to_groups(action_dir, total_frames, group_size=GROUP_SIZE):
    """生成临时group"""
    total_groups = ceil(total_frames / group_size)
    print(f"📦 开始分组：共{total_frames}帧 → 分{total_groups}组（每组{group_size}帧）")
    
    action_basename = os.path.basename(action_dir)
    action_unique_id = action_basename.replace("actions_", "")
    group_info_list = []
    
    for group_idx in tqdm(range(total_groups), desc="生成临时group"):
        start_frame = group_idx * group_size
        end_frame = min((group_idx + 1) * group_size - 1, total_frames - 1)
        group_unique_name = f"group_{action_unique_id}_{group_idx + 1:03d}"
        temp_group_path = os.path.join(action_dir, group_unique_name)
        os.makedirs(temp_group_path, exist_ok=True)
        
        for frame_idx in range(start_frame, end_frame + 1):
            frame_prefix = f"frame_{frame_idx:06d}"
            files_to_copy = [f"{frame_prefix}_RGB.png", f"{frame_prefix}_depth.npy", f"{frame_prefix}_camera.json"]
            for filename in files_to_copy:
                src = os.path.join(action_dir, filename)
                dst = os.path.join(temp_group_path, filename)
                if os.path.exists(src):
                    shutil.copy2(src, dst)
        
        group_info_list.append((temp_group_path, group_unique_name))
    
    print(f"✅ 临时分组完成！当前action共生成{len(group_info_list)}个group")
    return group_info_list

def move_single_action_groups(group_info_list, root_dir, action_dir):
    """移动当前action的group到根目录"""
    print(f"\n📤 开始移动{os.path.basename(action_dir)}的group到根目录")
    success_count = 0
    all_moved = True
    
    for temp_group_path, group_unique_name in tqdm(group_info_list, desc="移动group"):
        target_group_path = os.path.join(root_dir, group_unique_name)
        
        try:
            if os.path.exists(target_group_path):
                print(f"   ⚠️ 目标group已存在，跳过：{group_unique_name}")
                all_moved = False
                continue
            
            shutil.move(temp_group_path, target_group_path)
            if os.path.exists(target_group_path):
                success_count += 1
            else:
                all_moved = False
        except Exception as e:
            print(f"   ❌ 移动报错：{str(e)}")
            all_moved = False
    
    print(f"\n📊 当前action group移动统计：成功{success_count}个")
    return all_moved

def delete_action_folder(action_dir):
    """删除action文件夹"""
    print(f"\n🗑️ 开始删除action文件夹：{os.path.basename(action_dir)}")
    try:
        shutil.rmtree(action_dir)
        if not os.path.exists(action_dir):
            print(f"✅ 成功删除action文件夹")
            return True
        else:
            print(f"❌ 删除失败")
            return False
    except Exception as e:
        print(f"❌ 删除报错：{str(e)}")
        return False

def process_single_action(action_dir, root_dir):
    """处理单个action"""
    action_name = os.path.basename(action_dir)
    print(f"\n{'='*60}")
    print(f"📂 开始处理action：{action_name}")
    print(f"{'='*60}")
    
    video_path = os.path.join(action_dir, "capture.mp4")
    if not os.path.exists(video_path):
        print(f"   ❌ 未找到capture.mp4，跳过该action")
        return False
    
    # 提取RGB帧
    total_frames = extract_rgb_from_video(video_path, action_dir)
    if total_frames == 0:
        return False
    
    # 生成临时group
    group_info_list = split_frames_to_groups(action_dir, total_frames)
    
    # 删除原始数据
    print(f"\n🗑️ 删除原始数据")
    if os.path.exists(video_path):
        os.remove(video_path)
        print(f"   ✅ 已删除视频文件")
    
    for frame_idx in tqdm(range(total_frames), desc="删除未分组帧"):
        frame_prefix = f"frame_{frame_idx:06d}"
        files_to_delete = [f"{frame_prefix}_RGB.png", f"{frame_prefix}_depth.npy", f"{frame_prefix}_camera.json"]
        for filename in files_to_delete:
            file_path = os.path.join(action_dir, filename)
            if os.path.exists(file_path):
                os.remove(file_path)
    
    # 移动group
    all_groups_moved = move_single_action_groups(group_info_list, root_dir, action_dir)
    
    # 删除action文件夹
    if all_groups_moved:
        delete_action_folder(action_dir)
    
    return True

def process_extracted_folder(folder_path):
    """处理解压后的文件夹（处理所有actions）"""
    print(f"\n{'='*60}")
    print(f"⚙️ 开始处理文件夹: {os.path.basename(folder_path)}")
    print(f"{'='*60}")
    
    # 查找所有actions文件夹
    action_dirs = sorted(glob.glob(os.path.join(folder_path, "actions_*")))
    
    if not action_dirs:
        print(f"⚠️ 未找到actions_开头的文件夹")
        return False
    
    print(f"📋 找到{len(action_dirs)}个actions文件夹")
    
    processed_count = 0
    for action_dir in action_dirs:
        if process_single_action(action_dir, folder_path):
            processed_count += 1
    
    print(f"\n✅ 文件夹处理完成：成功处理{processed_count}/{len(action_dirs)}个action")
    return processed_count > 0

# ==================== OSS上传模块 ====================
# ==================== OSS上传模块（修改版）====================
# ==================== OSS上传模块（带进度条版本）====================
def get_game_name_from_folder(folder_name):
    """从文件夹名称提取游戏名称"""
    # 假设格式为：游戏名-日期-其他信息
    # 例如：赛博朋克2077-20251016-F9-02-zzx
    game_name = folder_name.split('-')[0]
    return game_name

def upload_tmp_to_oss(tmp_path, oss_base_path):
    # """
    # 直接上传整个tmp文件夹到OSS（带进度显示）
    # tmp_path: C:\Users\10762\Desktop\data\tmp\
    # 上传到: oss://bucket/cyh/game_data/游戏名/
    
    # OSS最终结构：
    # oss://bucket/cyh/game_data/赛博朋克2077/
    #     ├── 赛博朋克2077-20251016-F9-02-zzx/
    #     │   ├── group_xxx_001/
    #     │   └── ...
    # """
    print(f"\n{'='*60}")
    print(f"☁️ 开始上传到OSS")
    print(f"{'='*60}")
    
    # 获取tmp文件夹下的子文件夹
    subfolders = [f for f in os.listdir(tmp_path) 
                  if os.path.isdir(os.path.join(tmp_path, f))]
    
    if not subfolders:
        print(f"⚠️ tmp文件夹为空，无需上传")
        return True
    
    # 从第一个文件夹名提取游戏名称
    first_folder = subfolders[0]
    game_name = get_game_name_from_folder(first_folder)
    
    # 构建OSS目标路径
    oss_target_path = f"{oss_base_path}{game_name}/"
    
    print(f"📁 本地路径: {tmp_path}")
    print(f"☁️ OSS路径: {oss_target_path}")
    print(f"🎮 游戏名称: {game_name}")
    print(f"📦 包含文件夹: {', '.join(subfolders)}")
    
    # 统计文件数量和大小
    print(f"\n📊 统计上传数据...")
    total_files = 0
    total_size = 0
    for folder in subfolders:
        folder_path = os.path.join(tmp_path, folder)
        for root, dirs, files in os.walk(folder_path):
            total_files += len(files)
            for file in files:
                file_path = os.path.join(root, file)
                try:
                    total_size += os.path.getsize(file_path)
                except:
                    pass
    
    print(f"   文件数量: {total_files}")
    print(f"   总大小: {total_size / (1024**3):.2f} GB")
    
    try:
        # 构建ossutil命令
        cmd = [
            OSSUTIL_PATH,
            'cp',
            '-r',           # 递归上传
            '-u',           # 只上传新文件或修改过的文件
            '--jobs', '3',  # 并发任务数（可以加快上传速度）
            tmp_path,
            oss_target_path
        ]
        
        print(f"\n🚀 执行命令: {' '.join(cmd)}")
        print(f"{'='*60}")
        
        # 实时显示输出（ossutil自带进度显示）
        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding='utf-8',
            errors='ignore',
            bufsize=1,
            universal_newlines=True
        )
        
        # 逐行输出，保留ossutil的进度显示
        for line in process.stdout:
            print(line, end='')
        
        # 等待进程结束
        return_code = process.wait()
        
        print(f"{'='*60}")
        
        if return_code == 0:
            print(f"✅ 上传成功！")
            return True
        else:
            print(f"❌ 上传失败！返回码: {return_code}")
            return False
            
    except FileNotFoundError:
        print(f"❌ 找不到ossutil命令，请检查OSSUTIL_PATH配置")
        print(f"当前配置: {OSSUTIL_PATH}")
        print(f"\n💡 提示：")
        print(f"   1. 下载ossutil: https://help.aliyun.com/document_detail/120075.html")
        print(f"   2. 配置ossutil: ossutil config")
        print(f"   3. 修改脚本中的OSSUTIL_PATH变量为ossutil.exe的完整路径")
        return False
    except Exception as e:
        print(f"❌ 上传出错: {str(e)}")
        import traceback
        traceback.print_exc()
        return False

# ==================== 清理模块 ====================
def cleanup_tmp_folder(tmp_path):
    """清空tmp文件夹内的所有内容"""
    print(f"\n{'='*60}")
    print(f"🗑️ 开始清理tmp文件夹")
    print(f"{'='*60}")
    
    try:
        for item in os.listdir(tmp_path):
            item_path = os.path.join(tmp_path, item)
            
            if os.path.isdir(item_path):
                print(f"   删除文件夹: {item}")
                shutil.rmtree(item_path)
            else:
                print(f"   删除文件: {item}")
                os.remove(item_path)
        
        # 验证是否清空
        remaining = os.listdir(tmp_path)
        if not remaining:
            print(f"✅ tmp文件夹已清空")
            return True
        else:
            print(f"⚠️ 仍有{len(remaining)}个项目未删除")
            return False
            
    except Exception as e:
        print(f"❌ 清理出错: {str(e)}")
        return False

# ==================== 主流程（串行处理）====================
def process_single_url(url, tmp_dir, oss_base_path):
    """
    处理单个URL的完整流程：
    1. 下载
    2. 解压到tmp/文件夹名/
    3. 处理actions
    4. 上传整个tmp文件夹
    5. 清空tmp
    """
    print(f"\n{'#'*60}")
    print(f"# 开始处理新的数据包")
    print(f"{'#'*60}")
    
    # 步骤1: 下载
    filename = extract_filename_from_url(url)
    zip_path = os.path.join(tmp_dir, filename)
    
    if not download_file(url, zip_path):
        print(f"❌ 下载失败，跳过此URL")
        return False
    
    # 步骤2: 解压
    extracted_folder = extract_zip(zip_path, tmp_dir)
    if not extracted_folder:
        print(f"❌ 解压失败，跳过此URL")
        return False
    
    # 步骤3: 处理
    if not process_extracted_folder(extracted_folder):
        print(f"❌ 处理失败，跳过上传")
        return False
    
    # 步骤4: 上传整个tmp文件夹（修改这里）
    if not upload_tmp_to_oss(tmp_dir, oss_base_path):
        print(f"❌ 上传失败，保留本地文件")
        return False
    
    # 步骤5: 清空tmp
    if not cleanup_tmp_folder(tmp_dir):
        print(f"⚠️ 清理失败，但继续处理下一个")
    
    print(f"\n{'#'*60}")
    print(f"# 当前数据包处理完成")
    print(f"{'#'*60}\n")
    
    return True

def main():
    parser = argparse.ArgumentParser(
        description="自动化数据处理流程（串行版本）：逐个下载→处理→上传→清理",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
使用示例：
  python script.py urls.txt
  
配置说明：
  1. 修改脚本开头的配置参数（BASE_DIR、OSS_BASE_PATH等）
  2. 确保已安装ossutil并配置好OSS访问权限
  3. 在urls.txt中每行放一个下载链接
  
流程说明：
  每个URL独立处理：
    下载 → 解压到tmp/文件夹/ → 处理actions → 上传tmp → 清空tmp → 下一个
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
        help="从第几个URL开始处理（用于断点续传，默认从第1个开始）"
    )
    parser.add_argument(
        "--skip-upload",
        action="store_true",
        help="跳过上传步骤（仅处理不上传，用于测试）"
    )
    parser.add_argument(
        "--keep-files",
        action="store_true",
        help="处理完成后保留本地文件（不清空tmp）"
    )
    
    args = parser.parse_args()
    
    # 检查URL文件
    if not os.path.exists(args.url_file):
        print(f"❌ URL文件不存在: {args.url_file}")
        return
    
    # 读取URL列表
    try:
        with open(args.url_file, 'r', encoding='utf-8') as f:
            urls = [line.strip() for line in f if line.strip() and not line.startswith('#')]
    except Exception as e:
        print(f"❌ 读取URL文件失败: {str(e)}")
        return
    
    if not urls:
        print(f"❌ URL文件为空")
        return
    
    # 创建tmp目录
    os.makedirs(BASE_DIR, exist_ok=True)
    
    # 显示配置信息
    print(f"\n{'#'*60}")
    print(f"# 自动化数据处理流程（串行版本）")
    print(f"{'#'*60}")
    print(f"📁 工作目录: {BASE_DIR}")
    print(f"☁️ OSS基础路径: {OSS_BASE_PATH}")
    print(f"📋 总URL数量: {len(urls)}")
    print(f"🚀 开始位置: 第{args.start_from}个")
    if args.skip_upload:
        print(f"⚠️ 跳过上传步骤（测试模式）")
    if args.keep_files:
        print(f"⚠️ 保留本地文件（不清空tmp）")
    print(f"{'#'*60}\n")
    
    # 全局确认
    print(f"⚠️ 处理流程：")
    print(f"   每个URL独立处理（下载→解压→处理→上传→清空tmp）")
    print(f"   处理完一个才会开始下一个")
    confirm = input(f"\n是否继续？(y/n): ")
    if confirm.lower() != 'y':
        print(f"✅ 已取消操作")
        return
    
    # 统计变量
    total_urls = len(urls)
    success_count = 0
    failed_urls = []
    
    # 串行处理每个URL
    try:
        for idx, url in enumerate(urls, 1):
            # 支持从指定位置开始
            if idx < args.start_from:
                print(f"⏭️ 跳过第{idx}个URL")
                continue
            
            print(f"\n{'='*60}")
            print(f"[总进度: {idx}/{total_urls}] 处理第{idx}个URL")
            print(f"{'='*60}")
            
            # 处理单个URL的完整流程
            try:
                if args.skip_upload:
                    # 测试模式：只下载和处理
                    filename = extract_filename_from_url(url)
                    zip_path = os.path.join(BASE_DIR, filename)
                    
                    if download_file(url, zip_path):
                        extracted_folder = extract_zip(zip_path, BASE_DIR)
                        if extracted_folder and process_extracted_folder(extracted_folder):
                            success_count += 1
                            print(f"✅ 第{idx}个URL处理成功（未上传）")
                        else:
                            failed_urls.append((idx, url))
                    else:
                        failed_urls.append((idx, url))
                        
                elif args.keep_files:
                    # 保留文件模式：不清空tmp
                    filename = extract_filename_from_url(url)
                    zip_path = os.path.join(BASE_DIR, filename)
                    
                    if download_file(url, zip_path):
                        extracted_folder = extract_zip(zip_path, BASE_DIR)
                        if extracted_folder and process_extracted_folder(extracted_folder):
                            if upload_tmp_to_oss(BASE_DIR, OSS_BASE_PATH):
                                success_count += 1
                                print(f"✅ 第{idx}个URL处理成功（已保留文件）")
                            else:
                                failed_urls.append((idx, url))
                        else:
                            failed_urls.append((idx, url))
                    else:
                        failed_urls.append((idx, url))
                        
                else:
                    # 正常模式：完整流程
                    if process_single_url(url, BASE_DIR, OSS_BASE_PATH):
                        success_count += 1
                        print(f"✅ 第{idx}个URL处理成功")
                    else:
                        failed_urls.append((idx, url))
                        print(f"❌ 第{idx}个URL处理失败")
                
            except Exception as e:
                print(f"❌ 处理第{idx}个URL时发生错误: {str(e)}")
                failed_urls.append((idx, url))
                import traceback
                traceback.print_exc()
            
            # 显示当前进度
            print(f"\n📊 当前进度: 成功{success_count}个，失败{len(failed_urls)}个，剩余{total_urls - idx}个")
    
    except KeyboardInterrupt:
        print(f"\n\n⚠️ 用户中断操作")
        print(f"已处理: {idx - 1}/{total_urls}")
    
    # 最终统计
    print(f"\n{'#'*60}")
    print(f"# 处理完成！")
    print(f"{'#'*60}")
    print(f"📊 最终统计：")
    print(f"   ✅ 成功: {success_count}/{total_urls}")
    print(f"   ❌ 失败: {len(failed_urls)}/{total_urls}")
    
    if failed_urls:
        print(f"\n❌ 失败的URL列表：")
        for idx, url in failed_urls:
            filename = extract_filename_from_url(url)
            print(f"   [{idx}] {filename}")
        
        # 保存失败列表
        failed_file = "failed_urls.txt"
        try:
            with open(failed_file, 'w', encoding='utf-8') as f:
                for idx, url in failed_urls:
                    f.write(f"{url}\n")
            print(f"\n💾 失败URL已保存到: {failed_file}")
            print(f"   可使用 --start-from 参数重新处理")
        except Exception as e:
            print(f"⚠️ 保存失败URL列表出错: {str(e)}")
    
    print(f"{'#'*60}\n")

if __name__ == '__main__':
    main()

