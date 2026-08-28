cmake_minimum_required(VERSION 3.14)
project("music_player" LANGUAGES CXX)

# Flutter windows 配置
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 资源编译器（用于 Windows 应用图标和清单）
set(APP_ICON_RESOURCE_WINDOWS "${CMAKE_CURRENT_SOURCE_DIR}/runner/resources.rc")

# Windows 应用清单（系统媒体传输控制 SMTC）
set(APP_MANIFEST_RESOURCE_WINDOWS "${CMAKE_CURRENT_SOURCE_DIR}/runner/Runner.rc")

# Windows 需要的特殊库
# - winmm: 音频
# - ole32: COM（SMTC）
# - shcore: DPI 感知
# - user32: 窗口管理
target_link_libraries(${BINARY_NAME} PRIVATE
  flutter
  flutter_wrapper_app
  "winmm"
  "ole32"
  "shcore"
  "user32"
  "dwmapi"
)

# Windows 安装配置
install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${INSTALL_BUNDLE_DIR}")
