#!/bin/bash

mkdir -p ~/printer_data/gcodes/plr

# 从 saved_variables.cfg 中提取文件路径和续打文件名
filepath=$(sed -n "s/.*filepath *= *'\([^']*\)'.*/\1/p" /home/sovol/printer_data/config/saved_variables.cfg)
filepath=$(printf "%s" "$filepath")
echo "filepath=$filepath"

last_file=$(sed -n "s/.*last_file *= *'\([^']*\)'.*/\1/p" /home/sovol/printer_data/config/saved_variables.cfg)
last_file=$(printf "%s" "$last_file")
echo "$last_file"

power_resume_z=$(sed -n "s/.*power_resume_z *= *\([0-9.]*\).*/\1/p" /home/sovol/printer_data/config/saved_variables.cfg)
power_resume_z=$(printf "%s" "$power_resume_z")

echo "power_resume_z=$power_resume_z"

plr=$last_file
PLR_PATH=~/printer_data/gcodes/plr

# 从 JSON 中提取高度与 commandline
height=$(jq -r '.Z' /home/sovol/sovol_plr_height)
commandline=$(jq -r '.commandline' /home/sovol/sovol_plr_height)

echo "height=$height"
echo "plr=$plr"

TMP_FILE="/home/sovol/plrtmpA.$$"

# 移除缩略图和 DOS 行尾，统一 Z 格式（Z2 -> Z2.0）
sed '/; thumbnail begin/,/; thumbnail end/d' "$filepath" | \
  sed 's/\r$//' | \
  awk -F"Z" 'BEGIN{OFS="Z"} {if ($2 ~ /^[0-9]+$/) $2=$2".0"} 1' > "$TMP_FILE"

# 写入头部注释
comment_content=$(grep '^;' "$filepath" | sed '/; thumbnail end/q')
echo "$comment_content" > "${PLR_PATH}/${plr}"

# 补充头部元数据
grep -E ';TIME:|;Layer height:|;MINX:|;MINY:|;MINZ:|;MAXX:|;MAXY:|;MAXZ:|;Generated with Sovol Slicer' "$TMP_FILE" >> "${PLR_PATH}/${plr}"

# 设置打印起始位置
echo "SET_KINEMATIC_POSITION Z=$height" >> "${PLR_PATH}/${plr}"

# 防止模型拉扯：热端加热
echo 'M109 S160' >> "${PLR_PATH}/${plr}"

# 抬升Z轴 & 回零XY
echo 'G91' >> "${PLR_PATH}/${plr}"
echo 'G1 Z5' >> "${PLR_PATH}/${plr}"
echo 'G90' >> "${PLR_PATH}/${plr}"
echo 'G28 X Y' >> "${PLR_PATH}/${plr}"  # For test

# 调整高度，防止撞模型
# 比较两个浮点数
if awk "BEGIN {exit !(\"$height\" == \"$power_resume_z\")}"
then
    adjusted_height=$(echo "$height + 10" | bc)
    echo "height==power_resume_z $height, $power_resume_z" >> ~/../mount.log
else
    adjusted_height=$(echo "$height + 9.4" | bc)
    echo "height!=power_resume_z $height, $power_resume_z" >> ~/../mount.log
fi

echo "SET_KINEMATIC_POSITION Z=$adjusted_height" >> "${PLR_PATH}/${plr}"

# 提取温度控制指令（M104, M140, M109, M190），写入续打文件  M104|M109|
sed "/ Z$height/q" "$TMP_FILE" | grep -E 'M140|M190' >> "${PLR_PATH}/${plr}"

# 提取 G-code 尾部注释中的温度信息
end_block=$(sed -n '/; CONFIG_BLOCK_START/,$p' "$TMP_FILE" | tr '\n' ' ' | sed -E 's/ ;[^ ]* //g' | sed -E 's/\\\\n/;/g')
# bed_temp=$(echo "$end_block" | tr ';' '\n' | grep 'material_bed_temperature' | sed -n 's/.* = /M190 S/p' | head -1)
print_temp=$(sed -n '/; CONFIG_BLOCK_START/,$p' "$TMP_FILE" | \
             grep '^; nozzle_temperature = ' | \
             sed -n 's/^; nozzle_temperature = /M109 S/p' | head -1)

[ -n "$print_temp" ] && echo "$print_temp" >> "${PLR_PATH}/${plr}"
# [ -n "$bed_temp" ] && echo "$bed_temp" >> "${PLR_PATH}/${plr}"


# 单独写一条风扇控制指令（50%功率）
echo "M106 S127" >> "${PLR_PATH}/${plr}"


# 等待温度达到
sed -i 's/^M140/M190/;s/^M104/M109/' "${PLR_PATH}/${plr}"
echo 'plr_temperature_wait' >> "${PLR_PATH}/${plr}"
echo 'M106 S255' >> "${PLR_PATH}/${plr}"

echo 'G91' >> "${PLR_PATH}/${plr}"
echo 'G1 E3' >> "${PLR_PATH}/${plr}"
echo 'G90' >> "${PLR_PATH}/${plr}"

# 恢复打印点坐标
f_value=12000
x_value=$(echo "$commandline" | grep -oP '(?<=X)[0-9.]+')
y_value=$(echo "$commandline" | grep -oP '(?<=Y)[0-9.]+')
z_value=$(echo "$commandline" | grep -oP '(?<=Z)[0-9.]+')

gcode_z="G0 Z$z_value"
gcode_xy="G0 F$f_value X$x_value Y$y_value"

echo "$gcode_xy" >> "${PLR_PATH}/${plr}"
echo "$gcode_z" >> "${PLR_PATH}/${plr}"

# 转义 commandline 中的 sed 特殊字符
sed_safe_cmd=$(printf '%s\n' "$commandline" | sed -e 's/[]\/.^$*[]/\\&/g')

# 从匹配点开始续写 G-code（流式读取，不占用大内存）
sed -n "/$sed_safe_cmd/,\$p" "$TMP_FILE" >> "${PLR_PATH}/${plr}"

# 清理临时文件
rm -f "$TMP_FILE"
