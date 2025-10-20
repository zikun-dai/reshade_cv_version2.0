#!/usr/bin/env python3
import os
import cv2
import glob
import shutil
import numpy as np
from PIL import Image
import argparse
from tqdm import tqdm
from math import ceil

def extract_rgb_from_video(video_path, output_dir):
    """复用原逻辑提取RGB帧，输出到当前action文件夹（临时存放）"""
    os.makedirs(output_dir, exist_ok=True)
    cap = cv2.VideoCapture(video_path)
    assert cap.isOpened(), f"❌ 无法打开视频文件: {video_path}"
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

def split_frames_to_groups(action_dir, total_frames, group_size=100):
    """在当前action内生成临时group，返回临时group信息（路径+名称）"""
    total_groups = ceil(total_frames / group_size)
    print(f"📦 开始分组：共{total_frames}帧 → 分{total_groups}组（每组{group_size}帧）")
    
    # 提取action唯一标识，确保group命名不重复
    action_basename = os.path.basename(action_dir)
    action_unique_id = action_basename.split("_")[-1]
    group_info_list = []  # 存储当前action的临时group信息
    
    for group_idx in tqdm(range(total_groups), desc="生成临时group"):
        start_frame = group_idx * group_size
        end_frame = min((group_idx + 1) * group_size - 1, total_frames - 1)
        group_unique_name = f"group_{action_unique_id}_{group_idx + 1:03d}"
        temp_group_path = os.path.join(action_dir, group_unique_name)
        os.makedirs(temp_group_path, exist_ok=True)
        
        # 复制帧文件到临时group
        for frame_idx in range(start_frame, end_frame + 1):
            frame_prefix = f"frame_{frame_idx:06d}"
            files_to_copy = [f"{frame_prefix}_RGB.png", f"{frame_prefix}_depth.npy", f"{frame_prefix}_camera.json"]
            for filename in files_to_copy:
                src = os.path.join(action_dir, filename)
                dst = os.path.join(temp_group_path, filename)
                if os.path.exists(src):
                    shutil.copy2(src, dst)
                else:
                    print(f"⚠️ 缺失文件：{src}，跳过复制")
        
        group_info_list.append((temp_group_path, group_unique_name))
        print(f"   ✅ 生成临时group：{os.path.basename(temp_group_path)}")
    
    print(f"✅ 临时分组完成！当前action共生成{len(group_info_list)}个group")
    return group_info_list

def move_single_action_groups(group_info_list, root_dir, action_dir):
    """移动当前action的group到根目录，返回移动成功状态（用于判断是否删除action文件夹）"""
    print(f"\n📤 开始移动{os.path.basename(action_dir)}的group到根目录")
    success_count = 0
    all_moved = True  # 标记当前action的group是否全部移动成功
    
    for temp_group_path, group_unique_name in tqdm(group_info_list, desc="移动当前action的group"):
        target_group_path = os.path.join(root_dir, group_unique_name)
        # 打印路径，方便排查
        print(f"   源路径：{os.path.basename(temp_group_path)}（位于{os.path.basename(action_dir)}内）")
        print(f"   目标路径：{os.path.join(os.path.basename(root_dir), group_unique_name)}")
        
        try:
            if os.path.exists(target_group_path):
                print(f"   ⚠️ 目标group已存在，跳过：{group_unique_name}")
                all_moved = False
                continue
            
            shutil.move(temp_group_path, target_group_path)
            # 验证移动结果
            if os.path.exists(target_group_path):
                print(f"   ✅ 移动成功：{group_unique_name}")
                success_count += 1
            else:
                print(f"   ❌ 移动失败：目标路径不存在")
                all_moved = False
        except Exception as e:
            print(f"   ❌ 移动报错：{str(e)}")
            all_moved = False
    
    # 统计当前action的移动结果
    print(f"\n📊 当前action group移动统计：成功{success_count}个，失败{len(group_info_list)-success_count}个")
    return all_moved  # 仅当所有group都移动成功时，才允许删除action文件夹

def delete_action_folder(action_dir):
    """删除当前action文件夹（仅在group全部移动成功后执行）"""
    print(f"\n🗑️ 开始删除已处理完成的action文件夹：{os.path.basename(action_dir)}")
    try:
        # 强制删除非空文件夹（确保清理彻底）
        shutil.rmtree(action_dir)
        # 验证删除结果
        if not os.path.exists(action_dir):
            print(f"✅ 成功删除action文件夹：{os.path.basename(action_dir)}")
            return True
        else:
            print(f"❌ 删除失败：action文件夹仍存在")
            return False
    except Exception as e:
        print(f"❌ 删除报错：{str(e)}（可能是文件夹被占用，建议关闭占用程序后重试）")
        return False

def process_single_action(action_dir, root_dir):
    """处理单个action的完整子流程：提取帧→分组→移动group→删除action文件夹"""
    action_name = os.path.basename(action_dir)
    print(f"\n==================================================")
    print(f"📂 开始处理单个action：{action_name}")
    
    # 1. 检查视频文件是否存在
    video_path = os.path.join(action_dir, "capture.mp4")
    if not os.path.exists(video_path):
        print(f"   ❌ 未找到capture.mp4，跳过该action")
        return False
    
    # 2. 提取RGB帧
    total_frames = extract_rgb_from_video(video_path, action_dir)
    
    # 3. 生成临时group
    group_info_list = split_frames_to_groups(action_dir, total_frames)
    
    # 4. 删除action内的原始数据（视频+未分组帧文件，避免占用空间）
    print(f"\n🗑️ 开始删除{action_name}内的原始数据（视频+未分组帧）")
    # 删除原始视频
    if os.path.exists(video_path):
        os.remove(video_path)
        print(f"   ✅ 已删除原始视频：capture.mp4")
    # 删除未分组帧文件
    deleted_count = 0
    for frame_idx in tqdm(range(total_frames), desc="删除未分组帧文件"):
        frame_prefix = f"frame_{frame_idx:06d}"
        files_to_delete = [f"{frame_prefix}_RGB.png", f"{frame_prefix}_depth.npy", f"{frame_prefix}_camera.json"]
        for filename in files_to_delete:
            file_path = os.path.join(action_dir, filename)
            if os.path.exists(file_path):
                os.remove(file_path)
                deleted_count += 1
    print(f"   ✅ 原始数据删除完成：共删除{deleted_count}个未分组帧文件")
    
    # 5. 移动当前action的group到根目录
    all_groups_moved = move_single_action_groups(group_info_list, root_dir, action_dir)
    
    # 6. 仅当所有group移动成功时，删除当前action文件夹
    if all_groups_moved:
        delete_action_folder(action_dir)
    else:
        print(f"⚠️ 当前action存在group移动失败，暂不删除action文件夹：{action_name}")
    
    print(f"📌 单个action {action_name} 处理结束\n")
    return True

def batch_process_actions(root_dir):
    """批量处理入口：逐个处理action，每处理完一个就移动group并删除该action"""
    # 匹配所有actions文件夹（按名称排序，确保处理顺序稳定）
    action_dirs = sorted(glob.glob(os.path.join(root_dir, "actions_*")))
    if not action_dirs:
        print(f"❌ 在根目录{root_dir}中未找到actions_开头的文件夹")
        return
    
    print(f"🎉 找到{len(action_dirs)}个actions文件夹，将逐个处理（处理完即删除）")
    processed_count = 0
    
    # 逐个处理每个action
    for action_dir in action_dirs:
        process_success = process_single_action(action_dir, root_dir)
        if process_success:
            processed_count += 1
    
    # 最终统计
    print(f"\n==================================================")
    print(f"🎉 所有actions处理完成！")
    print(f"📊 总处理统计：共找到{len(action_dirs)}个action，成功处理{processed_count}个")
    # 统计根目录最终的group数量
    root_group_count = len([f for f in os.listdir(root_dir) if f.startswith("group_") and os.path.isdir(os.path.join(root_dir, f))])
    print(f"📌 根目录最终包含{root_group_count}个group文件夹")

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="批量处理：逐个action→移动group→删除action文件夹（即时清理版）")
    parser.add_argument(
        "root_dir", 
        help="根目录路径（必须是你指定的路径：C:\\Users\\10762\\Downloads\\赛博朋克2077-20251016-F9-02-mjc\\赛博朋克2077-20251016-F9-02-mjc）"
    )
    args = parser.parse_args()
    
    # 验证根目录存在
    if not os.path.isdir(args.root_dir):
        print(f"❌ 根目录{args.root_dir}不存在，请检查路径是否正确")
    else:
        # 全局安全确认（避免误操作）
        confirm = input(f"⚠️ 警告：操作会逐个处理action，处理完后立即删除该action文件夹。是否继续？（输入y确认，其他键取消）：")
        if confirm.lower() == "y":
            batch_process_actions(args.root_dir)
        else:
            print(f"✅ 已取消操作，未修改任何文件")