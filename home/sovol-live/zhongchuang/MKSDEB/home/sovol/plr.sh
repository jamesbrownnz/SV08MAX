#!/bin/bash
mkdir -p ~/printer_data/gcodes/plr
filepath=$(sed -n "s/.*filepath *= *'\([^']*\)'.*/\1/p" /home/sovol/printer_data/config/saved_variables.cfg)
filepath=$(printf "$filepath")
echo "filepath=$filepath"
last_file=$(sed -n "s/.*last_file *= *'\([^']*\)'.*/\1/p" /home/sovol/printer_data/config/saved_variables.cfg)
last_file=$(printf "$last_file")
echo "$last_file"
plr=$last_file

height=$(jq -r '.Z' /home/sovol/sovol_plr_height)
commandline=$(jq -r '.commandline' /home/sovol/sovol_plr_height)
# extrude_type=$(jq -r '.extrude_type' /home/sovol/sovol_plr_height)
# e_extrude_abs=$(jq -r '.e_extrude_abs' /home/sovol/sovol_plr_height)

echo "height=$height"	#打印出Z轴高度
echo "plr=$plr" 		#打印续打文件路径

TMP_FILE=/home/sovol/plrtmpA.$$

PLR_PATH=~/printer_data/gcodes/plr
sed '/; thumbnail begin/,/; thumbnail end/d' "$filepath" | \
  sed 's/\r$//' | \
  awk -F"Z" 'BEGIN{OFS="Z"} {if ($2 ~ /^[0-9]+$/) $2=$2".0"} 1' > /home/sovol/plrtmpA.$$

comment_content=$(grep '^;' "$filepath" | sed '/; thumbnail end/q')
echo "$comment_content" > ${PLR_PATH}/"${plr}"
for tag in ';TIME:' ';Layer height:' ';MINX:' ';MINY:' ';MINZ:' ';MAXX:' ';MAXY:' ';MAXZ:' ';Generated with Sovol Slicer'; do
    grep "$tag" "$TMP_FILE" >> "${PLR_PATH}/${plr}"
done

echo "SET_KINEMATIC_POSITION Z=$height" >> ${PLR_PATH}/"${plr}"


#升温防止扯模型
echo 'M109 S160' >> ${PLR_PATH}/"${plr}"
# echo 'M190 S65' >> ${PLR_PATH}/"${plr}"

#抬升z轴，XY回零
echo 'G91' >> ${PLR_PATH}/"${plr}"
echo 'G1 Z5' >> ${PLR_PATH}/"${plr}"
echo 'G90' >> ${PLR_PATH}/"${plr}"
echo 'G28 X Y' >> ${PLR_PATH}/"${plr}"   #for test

if [[ "$commandline" == *"F"* ]]; then
    adjusted_height=$(echo "$height + 5" | bc)
else
    adjusted_height=$(echo "$height + 5" | bc)
fi

echo "SET_KINEMATIC_POSITION Z=$adjusted_height" >> ${PLR_PATH}/"${plr}"  #chris

# 获取加热相关 G-code（恢复高度之前）
sed "/ Z$height/q" "$TMP_FILE" | grep -E 'M104|M140|M109|M190|M106' >> "${PLR_PATH}/${plr}"

# 提取 End of Gcode 之后的所有注释，并处理为一行
end_block=$(sed -n '/;End of Gcode/,$p' "$TMP_FILE" | tr '\n' ' ' | \
            sed -E 's/ ;[^ ]* //g' | sed -E 's/\\\\n/;/g')

# 从中提取温度参数并转换为 G-code
bed_temp=$(echo "$end_block" | tr ';' '\n' | grep 'material_bed_temperature' | sed -n 's/.* = /M190 S/p' | head -1)
print_temp=$(echo "$end_block" | tr ';' '\n' | grep 'material_print_temperature' | sed -n 's/.* = /M109 S/p' | head -1)

# 写入到续打文件
[ -n "$bed_temp" ] && echo "$bed_temp" >> "${PLR_PATH}/${plr}"
[ -n "$print_temp" ] && echo "$print_temp" >> "${PLR_PATH}/${plr}"

# 改为等待温度
cat "${PLR_PATH}/${plr}" | sed -i 's/^M140/M190/;s/^M104/M109/' "${PLR_PATH}/${plr}"
echo 'plr_temperature_wait' >> "${PLR_PATH}/${plr}"
echo 'M106 S255' >> "${PLR_PATH}/${plr}"

#移动到续打点
f_value=10000
x_value=$(echo "$commandline" | grep -oP '(?<=X)[0-9.]+')
y_value=$(echo "$commandline" | grep -oP '(?<=Y)[0-9.]+')
z_value=$(echo "$commandline" | grep -oP '(?<=Z)[0-9.]+')


gcode_z="G0 Z$z_value" #for test
gcode_xy="G0 F$f_value X$x_value Y$y_value"  #for test


echo $gcode_xy >> ${PLR_PATH}/"${plr}" #for test
echo $gcode_z >> ${PLR_PATH}/"${plr}"

#复制后续gcode
sed -n "/$commandline/,\$p" /home/sovol/plrtmpA.$$ >> ${PLR_PATH}/"${plr}"

#删除中间文件
rm /home/sovol/plrtmpA.$$
