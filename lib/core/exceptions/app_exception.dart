/// 应用异常类型
enum ExceptionType {
  /// 网络错误
  network,

  /// 认证错误 (API Key 无效等)
  authentication,

  /// 引擎包未找到
  packNotFound,

  /// 数据解析错误
  parseError,

  /// 域名不允许
  domainNotAllowed,

  /// 未知错误
  unknown,
}

/// 统一的应用异常类
class AppException implements Exception {
  /// 异常类型
  final ExceptionType type;

  /// 错误消息
  final String message;

  /// 详细信息（用于调试）
  final String? details;

  /// 原始异常
  final Object? originalError;

  AppException({
    required this.type,
    required this.message,
    this.details,
    this.originalError,
  });

  /// 创建网络错误
  factory AppException.network(String message, {String? details, Object? error}) {
    return AppException(
      type: ExceptionType.network,
      message: message,
      details: details,
      originalError: error,
    );
  }

  /// 创建认证错误
  factory AppException.authentication(String message, {String? details}) {
    return AppException(
      type: ExceptionType.authentication,
      message: message,
      details: details,
    );
  }

  /// 创建引擎包未找到错误
  factory AppException.packNotFound(String packId) {
    return AppException(
      type: ExceptionType.packNotFound,
      message: '引擎包未找到: $packId',
      details: '请检查引擎包是否已安装',
    );
  }

  /// 创建解析错误
  factory AppException.parseError(String message, {String? details, Object? error}) {
    return AppException(
      type: ExceptionType.parseError,
      message: message,
      details: details,
      originalError: error,
    );
  }

  /// 创建域名不允许错误
  factory AppException.domainNotAllowed(String domain, List<String> allowedDomains) {
    return AppException(
      type: ExceptionType.domainNotAllowed,
      message: '域名未授权: $domain',
      details: '允许的域名: ${allowedDomains.join(", ")}',
    );
  }

  /// 创建未知错误
  factory AppException.unknown(String message, {Object? error}) {
    return AppException(
      type: ExceptionType.unknown,
      message: message,
      originalError: error,
    );
  }

  /// 获取用户友好的错误消息
  String getUserMessage() {
    switch (type) {
      case ExceptionType.network:
        return '网络连接失败，请检查网络设置';
      case ExceptionType.authentication:
        return 'API Key 无效或已过期，请检查设置';
      case ExceptionType.packNotFound:
        return message;
      case ExceptionType.parseError:
        return '数据解析失败，请稍后重试';
      case ExceptionType.domainNotAllowed:
        return '请求被拒绝：$message';
      case ExceptionType.unknown:
        return '发生未知错误：$message';
    }
  }

  @override
  String toString() {
    final buffer = StringBuffer('AppException(${type.name}): $message');
    if (details != null) {
      buffer.write('\nDetails: $details');
    }
    if (originalError != null) {
      buffer.write('\nOriginal: $originalError');
    }
    return buffer.toString();
  }
}
