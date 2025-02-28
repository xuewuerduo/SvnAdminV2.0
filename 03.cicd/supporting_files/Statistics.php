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
    public function GetLoadInfo()
    {
        /**
         * ----------1、负载计算开始----------
         */
        $loadavgArray = sys_getloadavg();

        // 获取CPU总核数（逻辑处理器数量）
        $cpuInfo = file_get_contents('/proc/cpuinfo');
        $cpuCount = substr_count($cpuInfo, 'processor'); // 更改为统计processor条目

        // 一分钟平均负载 / CPU核数 * 100，超过100则设为100
        $percent = round(($loadavgArray[0] / $cpuCount) * 100, 1);
        if ($percent > 100) {
            $percent = 100;
        }

        $data['load'] = [
            'cpuLoad15Min' => $loadavgArray[2],
            'cpuLoad5Min' => $loadavgArray[1],
            'cpuLoad1Min' => $loadavgArray[0],
            'percent' => $percent,
            'color' => funGetColor($percent)['color'],
            'title' => funGetColor($percent)['title']
        ];

        /**
         * ----------2、cpu利率用开始----------
         */
        // 获取第一次采样的 CPU 统计信息及时间
        $procStat1 = @file_get_contents('/proc/stat');
        if ($procStat1 === false) {
            // 处理错误，例如记录日志或设置默认值
            $data['cpuUsage'] = ['error' => 'Failed to read /proc/stat'];
            return;
        }

        if (!preg_match('/^cpu\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)(?:\s+\d+)*/m', $procStat1, $matches1)) {
            // 正则匹配失败处理
            $data['cpuUsage'] = ['error' => 'Invalid /proc/stat format'];
            return;
        }
        $totalCpuTime1 = array_sum(array_slice($matches1, 1, 8)); // 仅取前8个字段避免新字段干扰
        $time1 = microtime(true);

        // 等待采样间隔（至少1秒）
        sleep(1);

        // 获取第二次采样的 CPU 统计信息及时间
        $procStat2 = @file_get_contents('/proc/stat');
        if ($procStat2 === false) {
            // 处理错误
            $data['cpuUsage'] = ['error' => 'Failed to read /proc/stat'];
            return;
        }

        if (!preg_match('/^cpu\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)(?:\s+\d+)*/m', $procStat2, $matches2)) {
            // 正则匹配失败处理
            $data['cpuUsage'] = ['error' => 'Invalid /proc/stat format'];
            return;
        }
        $totalCpuTime2 = array_sum(array_slice($matches2, 1, 8));
        $time2 = microtime(true);

        // 计算实际时间差（秒）
        $elapsed = max($time2 - $time1, 0.001); // 避免除零错误

        // 计算 CPU 时间差
        $totalDiff = $totalCpuTime2 - $totalCpuTime1;
        if ($totalDiff <= 0) {
            $cpuAvgUsage = 0; // 时间差异常时设为0%
        } else {
            $idleDiff = $matches2[4] - $matches1[4]; // 第4字段为idle时间
            $cpuAvgUsage = 100 * (1 - ($idleDiff / $totalDiff));
            $cpuAvgUsage = max(min(round($cpuAvgUsage, 1), 100), 0); // 限制在0-100%
        }

        $data['cpuUsage'] = [
            'percent' => $cpuAvgUsage,
            'color' => funGetColor($cpuAvgUsage)['color'],
            'title' => funGetColor($cpuAvgUsage)['title']
        ];

        /**
         * 解析CPU信息（支持多路CPU、超线程、异构架构）
         */
        $cpuModelArray = [];
        $cpuPhysicalMap = [];  // 物理CPU映射表 [physical_id => cores]
        $cpuProcessorTotal = 0;

        // 按空行分割逻辑处理器块
        $procCpuinfo = file_get_contents('/proc/cpuinfo');
        $blocks = array_filter(explode("\n\n", trim($procCpuinfo)));

        foreach ($blocks as $block) {
            $cpuProcessorTotal++;  // 每个块对应一个逻辑处理器
            $currentPhysicalId = null;
            $currentModelName = null;
            $currentCores = null;

            // 解析块内字段
            foreach (explode("\n", trim($block)) as $line) {
                if (strpos($line, ':') === false) continue;
                list($key, $value) = explode(':', $line, 2);
                $key = trim($key);
                $value = trim($value);

                switch ($key) {
                    case 'model name':
                        $currentModelName = $value;
                        break;
                    case 'physical id':
                        $currentPhysicalId = $value;
                        break;
                    case 'cpu cores':
                        $currentCores = (int)$value;
                        break;
                }
            }

            // 处理单物理CPU场景（无physical id字段）
            if ($currentPhysicalId === null) {
                $currentPhysicalId = 0;  // 默认物理ID
            }

            // 记录物理CPU核心数（确保每个ID只记录一次）
            if (!isset($cpuPhysicalMap[$currentPhysicalId])) {
                $cpuPhysicalMap[$currentPhysicalId] = $currentCores ?? 0;
            }

            // 记录CPU型号（异构场景支持）
            if ($currentModelName !== null && !in_array($currentModelName, $cpuModelArray)) {
                $cpuModelArray[] = $currentModelName;
            }
        }

        // 统计指标
        $cpuPhysical = count($cpuPhysicalMap);          // 物理CPU个数
        $cpuCoreTotal = array_sum($cpuPhysicalMap);     // 总物理核心数
        $cpuLogicalTotal = $cpuProcessorTotal;          // 逻辑处理器总数

        $data['cpu'] = [
            'models'         => $cpuModelArray,        // 型号列表（支持异构）
            'physical_count' => $cpuPhysical,          // 物理CPU个数
            'cores_total'    => $cpuCoreTotal,         // 总物理核心数
            'logical_total'  => $cpuLogicalTotal,      // 逻辑处理器总数
            'percent'        => round($cpuAvgUsage, 1),
            'color'          => funGetColor($cpuAvgUsage)['color']
        ];

        /**
         * ----------4、内存计算开始----------
         */
        $meminfo = file_get_contents('/proc/meminfo');

        preg_match_all('/^([a-zA-Z()_0-9]+)\s*\:\s*([\d\.]+)\s*([a-zA-z]*)$/m', $meminfo, $meminfos);

        $meminfos = array_combine($meminfos[1], $meminfos[2]);
        $memTotal = (int)$meminfos['MemTotal'];
        $memUsed = $memTotal - (int)$meminfos['MemFree'] - (int)$meminfos['Cached'] - (int)$meminfos['Buffers'] -  (int)$meminfos['SReclaimable'];
        $memFree = $memTotal - $memUsed;

        $percent = round($memUsed / $memTotal * 100, 1);

        $data['mem'] = [
            'memTotal' => round($memTotal / 1024),
            'memUsed' => round($memUsed / 1024),
            'memFree' => round($memFree / 1024),
            'percent' => $percent,
            'color' => funGetColor($percent)['color']
        ];

        return message(200, 1, '成功', $data);
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
                            'color' => funGetColor($diskUsage['percent'])['color']
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