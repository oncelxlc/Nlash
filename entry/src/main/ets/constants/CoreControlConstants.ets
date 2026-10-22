// UI 与 Extension 的控制事件名称；命令、响应和增量进度使用独立通道。
export const CORE_COMMAND_EVENT = 'com.zhexian.nlash.event.CORE_COMMAND';

export const CORE_RESPONSE_EVENT = 'com.zhexian.nlash.event.CORE_RESPONSE';

export const CORE_PROGRESS_EVENT = 'com.zhexian.nlash.event.CORE_PROGRESS';

export const CORE_CONTROL_VERSION = 1;

export const MAX_CORE_COMMAND_LENGTH = 16 * 1024;

export const MAX_CORE_RESPONSE_LENGTH = 1024 * 1024;

// CommonEvent data 上限为 64 KiB；每个 UTF-16 单元最坏会转义为 6 字节，另留信封空间。
export const CORE_RESPONSE_CHUNK_LENGTH = 8 * 1024;

export const MAX_CORE_RESPONSE_CHUNKS = MAX_CORE_RESPONSE_LENGTH / CORE_RESPONSE_CHUNK_LENGTH;

export const MAX_CORE_PROGRESS_LENGTH = 8 * 1024;
