<?php
/*
 * @Author: witersen
 * 
 * @LastEditors: witersen
 * 
 * @Description: QQ:1801168257
 */

namespace app\service;

class Statistics extends Base
{
    function __construct($parm = [])
    {
        parent::__construct($parm);
    }

    /**
     * 获取状态
     *
     * 负载状态
     * CPU使用率
     * 内存使用率
     */
    public function GetLoadInfo() {
        $data = ['load' => [], 'cpu' => [], 'mem' => []];

        try {
            // 统一获取CPU核心数
            $cpuCount = function_exists('shell_exec') ? (int)shell_exec('nproc --all') : 1;
            $cpuCount = max($cpuCount, 1);

            /**
             * 1. 负载计算
             */
            $loadavgArray = sys_getloadavg();
            if (empty($loadavgArray)) throw new Exception("sys_getloadavg failed");

            $loadPercent = round(($loadavgArray[0] / $cpuCount) * 100, 1);
            $data['load'] = [
                'cpuLoad15Min' => $loadavgArray[2],
                'cpuLoad5Min' => $loadavgArray[1],
                'cpuLoad1Min' => $loadavgArray[0],
                'percent' => min($loadPercent, 200),
                'color' => $this->funGetColor($loadPercent)['color'],
                'title' => $this->funGetColor($loadPercent)['title']
            ];

            /**
             * 2. CPU利用率计算
             */
            // 第一次采样
            $stat1 = file('/proc/stat');
            if (empty($stat1)) throw new Exception("Cannot read /proc/stat");
            $times1 = preg_split('/\s+/', trim($stat1[0]));
            array_shift($times1); // 移除"cpu"标识
            $total1 = array_sum(array_map('intval', $times1));
            $idle1 = $times1[3] + ($times1[4] ?? 0); // idle + iowait

            sleep(1);

            // 第二次采样
            $stat2 = file('/proc/stat');
            $times2 = preg_split('/\s+/', trim($stat2[0]));
            array_shift($times2);
            $total2 = array_sum(array_map('intval', $times2));
            $idle2 = $times2[3] + ($times2[4] ?? 0);

            // 计算利用率
            $totalDiff = $total2 - $total1;
            $idleDiff = $idle2 - $idle1;
            $cpuTotalUsage = ($totalDiff > 0) ? 100 * (1 - $idleDiff / $totalDiff) : 0;
            $cpuAvgUsage = round($cpuTotalUsage / $cpuCount, 1);

            /**
             * 3. CPU硬件信息
             */
            $cpuInfo = $this->parseCpuInfo();
            $data['cpu'] = [
                'percent' => max(0, min($cpuAvgUsage, 100)), //使用率
                'cpu' => array_unique(array_column($cpuInfo['physical'], 'model')), //CPU信息
                'cpuPhysical' => count($cpuInfo['physical']), //物理CPU个数
                'cpuCore' => array_sum(array_column($cpuInfo['physical'], 'cores')), //物理CPU总核心数
                'cpuProcessor' => count($cpuInfo['logical']),
                'hyperthreading' => ($cpuInfo['physical'][0]['siblings'] ?? 0) > ($cpuInfo['physical'][0]['cores'] ?? 1),
                'topology' => $cpuInfo['physical'],
                'color' => $this->funGetColor($loadPercent)['color']
            ];

            /**
             * 4. 内存计算
             */
            $meminfos = $this->parseMemInfo();
            $memTotal = $meminfos['MemTotal'] ?? 0;
            $memUsed = $memTotal
                - ($meminfos['MemFree'] ?? 0)
                - ($meminfos['Buffers'] ?? 0)
                - ($meminfos['Cached'] ?? 0)
                - ($meminfos['SReclaimable'] ?? 0);
            $memFree = $memTotal - $memUsed;

            $memPercent = $memTotal > 0 ? round($memUsed / $memTotal * 100, 1) : 0;
            $data['mem'] = [
                'memTotal' => round($memTotal / 1024, 1),   // MB
                'memUsed' => round($memUsed / 1024, 1),
                'memFree' => round($memFree / 1024),
                'percent' => $memPercent,
                'color' => $this->funGetColor($memPercent)['color']
            ];

            return message(200, 1, '成功', $data);
        } catch (Exception $e) {
            error_log("System Monitor Error: " . $e->getMessage());
            return message(500, 0, '数据采集失败', null);
        }
    }

// 辅助方法：解析CPU信息
    private function parseCpuInfo() {
        $info = ['physical' => [], 'logical' => []];
        $currentProc = -1;

        foreach (explode("\n", @file_get_contents('/proc/cpuinfo')) as $line) {
            if (preg_match('/^processor\s*:\s*(\d+)/', $line, $match)) {
                $currentProc = (int)$match[1];
                $info['logical'][$currentProc] = [];
            } elseif ($currentProc >= 0 && strpos($line, ':') !== false) {
                list($k, $v) = explode(':', $line, 2);
                $info['logical'][$currentProc][trim($k)] = trim($v);
            }
        }

        // 分析物理CPU
        foreach ($info['logical'] as $proc) {
            if (!isset($proc['physical id'], $proc['cpu cores'])) continue;

            $pid = $proc['physical id'];
            if (!isset($info['physical'][$pid])) {
                $info['physical'][$pid] = [
                    'model' => $proc['model name'] ?? $proc['Processor'] ?? 'Unknown',
                    'cores' => (int)$proc['cpu cores'],
                    'siblings' => (int)($proc['siblings'] ?? 1)
                ];
            }
        }

        return $info;
    }

// 辅助方法：解析内存信息
    private function parseMemInfo() {
        $meminfo = [];
        $content = @file_get_contents('/proc/meminfo');

        if ($content) {
            preg_match_all('/^([a-zA-Z()_0-9]+)\s*:\s*([\d]+)\s*kB$/m', $content, $matches);
            if (!empty($matches[1])) {
                $meminfo = array_combine($matches[1], array_map('intval', $matches[2]));
            }
        }

        // 确保必要字段存在
        $required = ['MemTotal', 'MemFree', 'Buffers', 'Cached', 'SReclaimable'];
        foreach ($required as $key) {
            if (!isset($meminfo[$key])) $meminfo[$key] = 0;
        }

        return $meminfo;
    }

// 颜色分级函数
    private function funGetColor($percent) {
        switch (true) {
            case $percent <= 70:
                return ['color' => '#67C23A', 'title' => '正常'];
            case $percent <= 90:
                return ['color' => '#E6A23C', 'title' => '警告'];
            default:
                return ['color' => '#F56C6C', 'title' => '严重'];
        }
    }

    /**
     * 获取磁盘信息
     */
    public function GetDiskInfo()
    {
        $diskArray = [];

        $diskStats = file_get_contents('/proc/mounts');
        $diskLines = explode("\n", $diskStats);

        $mountedPoints = [];

        foreach ($diskLines as $line) {
            if (!empty($line) && strpos($line, '/') === 0) {
                $diskInfo = explode(" ", $line);
                $mountedOn = trim($diskInfo[1]);
                $filesystem = trim($diskInfo[0]);

                if (!in_array($filesystem, $mountedPoints)) {
                    $mountedPoints[] = $filesystem;
                    $diskUsage = $this->GetDiskUsage($mountedOn);
                    if ($diskUsage) {
                        $diskArray[] = [
                            'fileSystem' => $filesystem,
                            'mountedOn' => $mountedOn,
                            'size' => $diskUsage['size'],
                            'used' => $diskUsage['used'],
                            'avail' => $diskUsage['avail'],
                            'percent' => $diskUsage['percent'],
                            'color' => $this->funGetColor($diskUsage)['color']
                        ];
                    }
                }
            }
        }



        return message(200, 1, '成功', $diskArray);
    }

    /**
     * 获取磁盘信息
     */
    private function GetDiskUsage($path)
    {
        $diskTotalSpace = disk_total_space($path);
        $diskFreeSpace = disk_free_space($path);

        if ($diskTotalSpace == 0) {
            return null;
        }

        $reservedSpace = $this->getReservedSpace($path);

        $diskUsage = $diskTotalSpace - $diskFreeSpace - $reservedSpace;

        $totalSize = funFormatSize($diskTotalSpace);
        $used = funFormatSize($diskUsage);
        $free = funFormatSize($diskFreeSpace);
        $percent = round(($diskUsage / $diskTotalSpace) * 100, 1);

        return [
            'size' => $totalSize,
            'used' => $used,
            'avail' => $free,
            'percent' => $percent
        ];
    }

    /**
     * 获取系统保留空间
     *
     * php5有效
     */
    private function GetReservedSpace($path)
    {
        if (!function_exists('statvfs')) {
            return 0;
        }

        $stat = @statvfs($path);

        if ($stat !== false) {
            $blockSize = $stat['bsize'];
            $blocks = $stat['blocks'];
            $freeBlocks = $stat['bfree'];
            $reservedBlocks = $stat['breserved'];

            $reservedSpace = $reservedBlocks * $blockSize;
            return $reservedSpace;
        }

        return 0;
    }

    /**
     * 获取统计
     *
     * 操作系统类型
     * 仓库占用体积
     * SVN仓库数量
     * SVN用户数量
     * SVN分组数量
     * 计划任务数量
     * 运行日志数量
     */
    public function GetStatisticsInfo()
    {
        $os = 'Unknown';
        $versionFiles = [
            '/etc/redhat-release',  // CentOS, RHEL
            '/etc/lsb-release',     // Ubuntu
            '/etc/debian_version',  // Debian
            '/etc/fedora-release',  // Fedora
            '/etc/SuSE-release',    // OpenSUSE
            '/etc/arch-release'     // Arch Linux
        ];
        foreach ($versionFiles as $file) {
            if (file_exists($file)) {
                $os = trim(file_get_contents($file));
                break;
            }
        }

        $aliaseCount = $this->SVNAdmin->GetAliaseInfo($this->authzContent);
        if (is_numeric($aliaseCount)) {
            $aliaseCount = -1;
        } else {
            $aliaseCount = count($aliaseCount);
        }

        $backupCount = 0;
        $files = scandir($this->configSvn['backup_base_path']);
        foreach ($files as $file) {
            if ($file != '.' && $file != '..') {
                if (!is_dir($this->configSvn['backup_base_path'] . '/' . $file)) {
                    $backupCount++;
                }
            }
        }

        return message(200, 1, '成功', [
            'os' => trim($os),

            'repCount' => $this->database->count('svn_reps'),
            'repSize' => funFormatSize($this->database->sum('svn_reps', 'rep_size')),

            'backupCount' => $backupCount,
            'backupSize' => funFormatSize(funGetDirSizeDu($this->configSvn['backup_base_path'])),

            'logCount' => $this->database->count('logs', ['log_id[>]' => 0]),

            'adminCount' => $this->database->count('admin_users'),
            'subadminCount' => $this->database->count('subadmin'),
            'userCount' => $this->database->count('svn_users'),
            'groupCount' => $this->database->count('svn_groups'),
            'aliaseCount' => $aliaseCount,
        ]);
    }
}