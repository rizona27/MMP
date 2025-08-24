import subprocess
import shutil
import os
import argparse
from datetime import datetime
import plistlib
import tempfile

class XcodeProjectBuilder:
    def __init__(self, project_path, output_folder=None, scheme_name=None):
        self.project_path = project_path
        self.output_folder = output_folder or os.path.join(project_path, "Build")
        self.scheme_name = scheme_name or "MMP"
        
        # 确保输出目录存在
        os.makedirs(self.output_folder, exist_ok=True)
        
    def get_project_info(self):
        """获取Xcode项目信息"""
        try:
            workspace_path = None
            project_path = None
            
            for item in os.listdir(self.project_path):
                if item.endswith('.xcworkspace'):
                    workspace_path = os.path.join(self.project_path, item)
                elif item.endswith('.xcodeproj'):
                    project_path = os.path.join(self.project_path, item)
            
            return workspace_path, project_path
        except Exception as e:
            print(f"获取项目信息时出错: {str(e)}")
            return None, None
    
    def find_entitlements_file(self):
        """查找Entitlements文件"""
        # 在项目目录中查找entitlements文件
        for root, dirs, files in os.walk(self.project_path):
            for file in files:
                if file.endswith('.entitlements'):
                    return os.path.join(root, file)
        
        # 如果没有找到，创建一个包含文件访问权限的entitlements文件
        entitlements_path = os.path.join(self.project_path, f"{self.scheme_name}.entitlements")
        self.create_file_access_entitlements(entitlements_path)
        return entitlements_path
    
    def create_file_access_entitlements(self, path):
        """创建包含文件访问权限的Entitlements文件"""
        entitlements = {
            'com.apple.security.files.user-selected.read-only': True,
            'com.apple.security.files.user-selected.read-write': True,
            'com.apple.security.files.downloads.read-only': True,
            'com.apple.security.files.downloads.read-write': True,
            'com.apple.security.app-sandbox': True,
            # 添加其他可能需要的权限
            'com.apple.security.network.client': True,
            'com.apple.security.device.camera': False,
            'com.apple.security.device.microphone': False,
        }
        
        with open(path, 'wb') as f:
            plistlib.dump(entitlements, f)
        
        print(f"已创建Entitlements文件: {path}")
        return path
    
    def embed_entitlements_in_binary(self, app_path):
        """将Entitlements信息嵌入到二进制文件中"""
        try:
            # 查找应用二进制文件
            binary_name = os.path.basename(app_path).replace('.app', '')
            binary_path = os.path.join(app_path, binary_name)
            
            if not os.path.exists(binary_path):
                print(f"警告: 未找到二进制文件 {binary_path}")
                return False
            
            # 使用codesign将entitlements信息嵌入到二进制文件
            entitlements_path = self.find_entitlements_file()
            embed_cmd = f"codesign --force --sign - --entitlements '{entitlements_path}' '{binary_path}'"
            
            print(f"嵌入Entitlements到二进制文件: {embed_cmd}")
            result = subprocess.run(embed_cmd, shell=True, capture_output=True, text=True)
            
            if result.returncode != 0:
                print(f"嵌入Entitlements失败: {result.stderr}")
                return False
            
            print("Entitlements已成功嵌入到二进制文件")
            return True
            
        except Exception as e:
            print(f"嵌入Entitlements时出错: {str(e)}")
            return False
    
    def build_ipa(self, configuration="Release"):
        """构建IPA文件，不进行签名但确保权限配置正确"""
        try:
            workspace_path, project_path = self.get_project_info()
            
            if not workspace_path and not project_path:
                print("错误: 未找到Xcode项目文件")
                return False
            
            # 查找或创建Entitlements文件
            entitlements_path = self.find_entitlements_file()
            print(f"使用Entitlements文件: {entitlements_path}")
            
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            archive_path = os.path.join(self.output_folder, f"Archive_{timestamp}.xcarchive")
            
            print(f"开始构建项目: {self.scheme_name}")
            
            # 构建archive - 不进行代码签名
            if workspace_path:
                archive_cmd = f"xcodebuild -workspace '{workspace_path}' -scheme '{self.scheme_name}' -configuration {configuration} -archivePath '{archive_path}' CODE_SIGN_IDENTITY=\"\" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO archive"
            else:
                archive_cmd = f"xcodebuild -project '{project_path}' -scheme '{self.scheme_name}' -configuration {configuration} -archivePath '{archive_path}' CODE_SIGN_IDENTITY=\"\" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO archive"
            
            print(f"执行命令: {archive_cmd}")
            result = subprocess.run(archive_cmd, shell=True, capture_output=True, text=True)
            
            if result.returncode != 0:
                print(f"构建失败: {result.stderr}")
                return False
            
            print("Archive构建成功")
            
            # 嵌入Entitlements到二进制文件
            app_path = os.path.join(archive_path, "Products/Applications", f"{self.scheme_name}.app")
            if not self.embed_entitlements_in_binary(app_path):
                print("警告: 嵌入Entitlements失败，但继续打包过程")
            
            # --- 核心修改部分 ---
            # 绕过 exportArchive，手动创建 IPA
            print("绕过 exportArchive，手动创建 IPA...")

            # 1. 创建一个临时目录来存放 Payload
            temp_dir = tempfile.mkdtemp()
            payload_path = os.path.join(temp_dir, "Payload")
            os.makedirs(payload_path)
            
            # 2. 将 .app 文件复制到 Payload 文件夹
            shutil.copytree(app_path, os.path.join(payload_path, f"{self.scheme_name}.app"))
            
            # 3. 创建 IPA
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            ipa_name = f"{self.scheme_name}_{timestamp}.ipa"
            final_ipa_path = os.path.join(self.output_folder, ipa_name)
            
            print("开始压缩 Payload 文件夹...")
            
            # 使用 shutil.make_archive 创建 zip 文件
            zip_path = shutil.make_archive(
                base_name=os.path.join(self.output_folder, f"{self.scheme_name}_{timestamp}"), 
                format='zip', 
                root_dir=temp_dir,
                base_dir='Payload'
            )
            
            # 将 zip 文件重命名为 ipa
            shutil.move(zip_path, final_ipa_path)
            
            print(f"IPA 文件已创建: {final_ipa_path}")
            
            # 将 Entitlements 文件复制到输出目录，供用户参考
            shutil.copy2(entitlements_path, os.path.join(self.output_folder, "AppEntitlements.plist"))
            print("Entitlements 文件已保存到输出目录，供重新签名时参考")
            
            # 清理临时文件
            shutil.rmtree(temp_dir)
            shutil.rmtree(archive_path, ignore_errors=True)
            
            return True
            # --- 核心修改部分结束 ---

        except Exception as e:
            print(f"构建过程中出错: {str(e)}")
            return False
            
    # 这个函数现在不再需要
    def create_export_options(self):
        return None

def main():
    parser = argparse.ArgumentParser(description='Xcode项目打包工具')
    parser.add_argument('--path', type=str, default='/Users/rizona/Documents/GitHub/MMP',
                        help='Xcode项目路径')
    parser.add_argument('--output', type=str, help='输出目录')
    parser.add_argument('--scheme', type=str, help='scheme名称')
    
    args = parser.parse_args()
    
    builder = XcodeProjectBuilder(args.path, args.output, args.scheme)
    
    success = builder.build_ipa()
    if success:
        print("IPA构建成功!")
        print("注意: 此IPA未进行签名，需要使用第三方工具重新签名")
        print("Entitlements文件已保存到输出目录，请确保重新签名时使用相同的权限配置")
        print("文件导入功能需要以下权限:")
        print("  - com.apple.security.files.user-selected.read-only")
        print("  - com.apple.security.files.user-selected.read-write")
        print("  - com.apple.security.files.downloads.read-only")
        print("  - com.apple.security.files.downloads.read-write")
    else:
        print("IPA构建失败!")
        exit(1)

if __name__ == "__main__":
    main()