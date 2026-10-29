import Darwin
import Foundation

struct LaunchRequest: Codable {
  var id = UUID().uuidString
  var paths: [String] = []
  var newWindow = false
  var newTab = false
  static func arguments(_ args: [String]) -> LaunchRequest {
    var request = LaunchRequest()
    for arg in args.dropFirst() {
      if arg == "--new-window" {
        request.newWindow = true
      } else if arg == "--new-tab" {
        request.newTab = true
      } else if !arg.hasPrefix("-") {
        request.paths.append(URL(fileURLWithPath: arg).standardizedFileURL.path)
      }
    }
    return request
  }
}
final class SingleInstance {
  var lockFD: Int32 = -1, socketFD: Int32 = -1
  let directory: String
  var path: String { directory + "/ipc" }
  var handler: ((LaunchRequest) -> Void)?
  private var pending: [LaunchRequest] = []
  private var handled = Set<String>()
  private let queue = DispatchQueue(label: "TinyEditor.IPC")
  init() {
    let isolated =
      ProcessInfo.processInfo.environment["TINYEDITOR_DATA_DIR"].map {
        "-" + contentDigest($0).prefix(6).map { String(format: "%02x", $0) }.joined()
      } ?? ""
    directory = "/tmp/TinyEditor-\(getuid())\(isolated)"
  }
  func acquireOrForward(_ request: LaunchRequest) throws -> Bool {
    if mkdir(directory, 0o700) != 0 && errno != EEXIST { throw TinyError("无法创建单实例通讯目录。") }
    var info = stat()
    guard lstat(directory, &info) == 0, info.st_uid == getuid(), (info.st_mode & S_IFMT) == S_IFDIR,
      (info.st_mode & 0o077) == 0
    else { throw TinyError("单实例通讯目录权限不安全。") }
    lockFD = open(directory + "/lock", O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
    guard lockFD >= 0 else { throw TinyError("无法打开单实例锁。") }
    if flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
      close(lockFD)
      lockFD = -1
      for _ in 0..<100 {
        if tryForward(request) { return false }
        usleep(50_000)
      }
      throw TinyError("已有 TinyEditor 正在启动或没有响应。请求尚未交付，请稍后重试。")
    }
    socketFD = socket(AF_UNIX, SOCK_STREAM, 0)
    guard socketFD >= 0 else { throw TinyError("无法创建本机通讯。") }
    unlink(path)
    var address = addressForPath()
    let count = socklen_t(MemoryLayout<sockaddr_un>.size)
    let bound = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(socketFD, $0, count) }
    }
    guard bound == 0, chmod(path, 0o600) == 0, listen(socketFD, 128) == 0 else {
      throw TinyError("无法监听本机通讯。")
    }
    queue.async { [weak self] in self?.acceptLoop() }
    return true
  }
  private func addressForPath() -> sockaddr_un {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    withUnsafeMutableBytes(of: &address.sun_path) { dest in
      dest.initializeMemory(as: UInt8.self, repeating: 0)
      for (i, byte) in path.utf8.enumerated() where i < dest.count - 1 { dest[i] = byte }
    }
    return address
  }
  private func configure(_ fd: Int32) {
    var timeout = timeval(tv_sec: 3, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    var yes: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
  }
  private func readLine(_ fd: Int32) -> Data? {
    var data = Data()
    var buf = [UInt8](repeating: 0, count: 4096)
    while data.count < 1_048_576 {
      let count = recv(fd, &buf, buf.count, 0)
      if count <= 0 { return nil }
      data.append(contentsOf: buf.prefix(count))
      if let index = data.firstIndex(of: 10) { return data.prefix(upTo: index) }
    }
    return nil
  }
  private func sendAll(_ fd: Int32, _ data: Data) -> Bool {
    data.withUnsafeBytes { bytes in
      guard let base = bytes.baseAddress else { return false }
      var sent = 0
      while sent < data.count {
        let count = send(fd, base.advanced(by: sent), data.count - sent, 0)
        if count <= 0 { return false }
        sent += count
      }
      return true
    }
  }
  private func tryForward(_ request: LaunchRequest) -> Bool {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return false }
    defer { close(fd) }
    configure(fd)
    var address = addressForPath()
    let result = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    guard result == 0, let data = try? JSONEncoder().encode(request),
      sendAll(fd, data + Data([10])), let ack = readLine(fd)
    else { return false }
    return String(data: ack, encoding: .utf8) == request.id
  }
  private func acceptLoop() {
    while socketFD >= 0 {
      let fd = accept(socketFD, nil, nil)
      if fd < 0 {
        if errno == EINTR { continue }
        return
      }
      configure(fd)
      if let data = readLine(fd),
        let request = try? JSONDecoder().decode(LaunchRequest.self, from: data)
      {
        if !handled.contains(request.id) {
          handled.insert(request.id)
          DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let handler = self.handler { handler(request) } else { self.pending.append(request) }
          }
        }
        _ = sendAll(fd, Data((request.id + "\n").utf8))
      }
      close(fd)
    }
  }
  func start(_ handler: @escaping (LaunchRequest) -> Void) {
    self.handler = handler
    let requests = pending
    pending.removeAll()
    requests.forEach(handler)
  }
  deinit {
    if socketFD >= 0 {
      shutdown(socketFD, SHUT_RDWR)
      close(socketFD)
    }
    if lockFD >= 0 {
      unlink(path)
      flock(lockFD, LOCK_UN)
      close(lockFD)
    }
  }
}
