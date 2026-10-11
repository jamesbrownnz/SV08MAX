#include "../include/MoonrakerAPI.h"
#include "../include/mks_error.h"
#include "../include/event.h"

#include <sys/sysinfo.h>
#include <stdarg.h>
#include <fcntl.h>
#include <unistd.h>

void mkslog_print(const char *fmt, ...)
{
    static pthread_mutex_t log_mutex = PTHREAD_MUTEX_INITIALIZER;
    time_t rawtime;
    struct tm *timeinfo;
    char datetime_str[64];
    char log_line[512];
    char msg_buf[400];  // 日志消息体

    // 格式化可变参数
    va_list args;
    va_start(args, fmt);
    vsnprintf(msg_buf, sizeof(msg_buf), fmt, args);
    va_end(args);

    // 获取当前时间
    time(&rawtime);
    timeinfo = localtime(&rawtime);
    strftime(datetime_str, sizeof(datetime_str), "%Y-%m-%d %H:%M:%S", timeinfo);

    // 构造完整日志行
    snprintf(log_line, sizeof(log_line), "[%s] %s\n", datetime_str, msg_buf);

    // 写入日志文件
    pthread_mutex_lock(&log_mutex);
    int fd = open(MKSLOG_PATH, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd != -1) {
        write(fd, log_line, strlen(log_line));
        fsync(fd);  // 强制刷新日志内容到磁盘
        close(fd);
    }
    pthread_mutex_unlock(&log_mutex);
    // 同时打印到控制台（或你原本的日志接口）
    MKSLOG_YELLOW("%s", msg_buf);
}

void parse_error(nlohmann::json error) {
    std::cout << error << std::endl;
}



