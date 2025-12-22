import struct
import re

def hex_to_floats(hex_str: str):
    # 1. 去掉所有非十六进制字符（空格、换行、逗号之类全删）
    cleaned = re.sub(r'[^0-9a-fA-F]', '', hex_str)
    
    floats = []
    # 2. 每 8 个十六进制字符对应 4 字节 = 1 个 float32
    # 不够 8 个的尾巴就自动丢弃
    for i in range(0, len(cleaned) - len(cleaned) % 8, 8):
        chunk = cleaned[i:i+8]              # 例如 "A4704541"
        b = bytes.fromhex(chunk)            # b"\xA4\x70\x45\x41"
        value = struct.unpack('<f', b)[0]   # 小端 float32
        floats.append(value)
    return floats

if __name__ == "__main__":
    # 示例：你可以把这串换成自己从 CE 复制出来的 16 进制
    hex_input = """
    FC 03 B2 44 DA 18 01 45 16 DE CB 42
    """
    result = hex_to_floats(hex_input)
    
    for idx, f in enumerate(result):
        print(f"{idx}: {f}")
