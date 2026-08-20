// ModelStore — explicit native model downloads with iOS background transfer.
// Model files live outside the vault and are validated before installation.
import CryptoKit
import Foundation
import Observation

struct AIModelDescriptor: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let detail: String
    let sizeLabel: String
    let expectedBytes: Int64
    let sha256: String
    let fileName: String
    let downloadURL: URL

    var storageKey: String { id.replacingOccurrences(of: "/", with: "-") }
}

enum AIModelCatalog {
    static let recommended: [AIModelDescriptor] = [
        AIModelDescriptor(
            id: "qwen3-1.7b-q8", name: "Qwen3 1.7B",
            detail: "Mais leve · rápido no dispositivo", sizeLabel: "1,83 GB",
            expectedBytes: 1_834_426_016,
            sha256: "061b54daade076b5d3362dac252678d17da8c68f07560be70818cace6590cb1a",
            fileName: "Qwen3-1.7B-Q8_0.gguf",
            downloadURL: URL(string: "https://huggingface.co/Qwen/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q8_0.gguf?download=true")!
        ),
        AIModelDescriptor(
            id: "phi-4-mini-q4", name: "Phi-4 Mini",
            detail: "Mais qualidade · exige mais memória", sizeLabel: "2,49 GB",
            expectedBytes: 2_491_874_688,
            sha256: "01999f17c39cc3074afae5e9c539bc82d45f2dd7faa3917c66cbef76fce8c0c2",
            fileName: "microsoft_Phi-4-mini-instruct-Q4_K_M.gguf",
            downloadURL: URL(string: "https://huggingface.co/bartowski/microsoft_Phi-4-mini-instruct-GGUF/resolve/main/microsoft_Phi-4-mini-instruct-Q4_K_M.gguf?download=true")!
        )
    ]
}

enum ModelDownloadError: LocalizedError {
    case invalidSize
    case invalidChecksum
    case missingDownload
    case httpStatus(Int)
    case moveFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidSize: return "O tamanho do modelo baixado não confere."
        case .invalidChecksum: return "A verificação do modelo falhou; ele não foi instalado."
        case .missingDownload: return "O download terminou sem um arquivo válido."
        case .httpStatus(let status): return "O servidor não entregou o modelo (HTTP \(status))."
        case .moveFailed(let reason): return "Não foi possível guardar o modelo baixado: \(reason)"
        }
    }
}

private enum ModelDownloadCompletion: Sendable {
    case success(URL)
    case failure(String)
}

@MainActor
@Observable
final class ModelStore {
    static let backgroundSessionIdentifier = "com.caiopieri.flint.model-downloads"
    static weak var activeStore: ModelStore?
    static var pendingBackgroundCompletion: (() -> Void)?

    let models = AIModelCatalog.recommended
    private(set) var installedModelIDs: Set<String> = []
    private(set) var downloadingModelID: String?
    private(set) var progress: Double = 0
    private(set) var bytesReceived: Int64 = 0
    private(set) var totalBytes: Int64 = 0
    private(set) var selectedModelID: String?
    private(set) var isDownloadPaused = false
    var errorMessage: String?

    private let selectedModelKey = "flint.ai.selected-model"
    private let pausedDownloadKey = "flint.ai.download-paused"
    private let savedBytesKey = "flint.ai.download-bytes"
    private let savedTotalBytesKey = "flint.ai.download-total-bytes"
    nonisolated static let activeDownloadKey = "flint.ai.active-download"
    private var session: URLSession?
    private var delegate: ModelDownloadDelegate?
    private var activeTask: URLSessionDownloadTask?
    private var activeTaskIdentifier: Int?
    private var finishedURLs: [Int: URL] = [:]
    private var completedTaskIDs: Set<Int> = []
    private var pausingTaskIDs: Set<Int> = []
    private var validationTasks: [Int: Task<Void, Never>] = [:]
    private var backgroundCompletionHandler: (() -> Void)?

    init() {
        selectedModelID = UserDefaults.standard.string(forKey: selectedModelKey)
        refreshInstalledModels()
        Self.activeStore = self

        let newDelegate = ModelDownloadDelegate(
            onProgress: { [weak self] taskID, received, total in
                Task { @MainActor in self?.handleProgress(taskID: taskID, received: received, total: total) }
            },
            onFinished: { [weak self] taskID, result in
                // The delegate has already moved the URLSession temporary file
                // before returning from didFinishDownloadingTo.
                Task { @MainActor in self?.handleFinished(taskID: taskID, result: result) }
            },
            onCompleted: { [weak self] taskID, error in
                Task { @MainActor in self?.handleCompleted(taskID: taskID, error: error) }
            },
            onEventsFinished: { [weak self] in
                Task { @MainActor in self?.finishBackgroundEvents() }
            }
        )
        delegate = newDelegate
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.backgroundSessionIdentifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.allowsCellularAccess = true
        session = URLSession(configuration: configuration, delegate: newDelegate, delegateQueue: nil)

        if let pending = Self.pendingBackgroundCompletion {
            backgroundCompletionHandler = pending
            Self.pendingBackgroundCompletion = nil
        }
        restoreActiveDownload()
    }

    func isInstalled(_ model: AIModelDescriptor) -> Bool { installedModelIDs.contains(model.id) }

    func modelURL(for id: String) -> URL? {
        guard let model = models.first(where: { $0.id == id }), isInstalled(model),
              let directory = try? modelsDirectory() else { return nil }
        return directory.appendingPathComponent(model.fileName, isDirectory: false)
    }

    func select(_ model: AIModelDescriptor) {
        selectedModelID = model.id
        UserDefaults.standard.set(model.id, forKey: selectedModelKey)
        if !isInstalled(model), downloadingModelID == nil { download(model) }
    }

    func download(_ model: AIModelDescriptor) {
        guard downloadingModelID == nil, !isInstalled(model), let session else { return }
        errorMessage = nil
        isDownloadPaused = false
        downloadingModelID = model.id
        progress = 0
        bytesReceived = 0
        totalBytes = model.expectedBytes
        let request = URLRequest(url: model.downloadURL, cachePolicy: .reloadIgnoringLocalCacheData)
        let task = session.downloadTask(with: request)
        activeTask = task
        activeTaskIdentifier = task.taskIdentifier
        UserDefaults.standard.set(model.id, forKey: Self.activeDownloadKey)
        task.taskDescription = model.id
        task.resume()
    }

    func pauseDownload() {
        guard let task = activeTask, let taskID = activeTaskIdentifier,
              let modelID = downloadingModelID, !isDownloadPaused else { return }
        isDownloadPaused = true
        pausingTaskIDs.insert(taskID)
        task.cancel { [weak self] resumeData in
            Task { @MainActor in
                self?.finishPause(taskID: taskID, modelID: modelID, resumeData: resumeData)
            }
        }
    }

    func resumeDownload() {
        guard isDownloadPaused, let modelID = downloadingModelID,
              let model = models.first(where: { $0.id == modelID }),
              let session else { return }
        do {
            let resumeData = try Data(contentsOf: resumeDataURL(for: modelID))
            let task = session.downloadTask(withResumeData: resumeData)
            task.taskDescription = model.id
            activeTask = task
            activeTaskIdentifier = task.taskIdentifier
            isDownloadPaused = false
            UserDefaults.standard.set(false, forKey: pausedDownloadKey)
            task.resume()
        } catch {
            errorMessage = "Não foi possível continuar o download: \(error.localizedDescription)"
        }
    }

    func cancelDownload() {
        activeTask?.cancel()
        if let id = activeTaskIdentifier { validationTasks[id]?.cancel() }
        clearActiveDownload()
    }

    func setBackgroundCompletionHandler(_ handler: @escaping () -> Void) {
        backgroundCompletionHandler = handler
    }

    private func restoreActiveDownload() {
        guard let modelID = UserDefaults.standard.string(forKey: Self.activeDownloadKey),
              let model = models.first(where: { $0.id == modelID }), let session else { return }
        downloadingModelID = model.id
        let storedTotal = UserDefaults.standard.integer(forKey: savedTotalBytesKey)
        let storedBytes = UserDefaults.standard.integer(forKey: savedBytesKey)
        totalBytes = storedTotal > 0 ? Int64(storedTotal) : model.expectedBytes
        bytesReceived = Int64(storedBytes)
        progress = totalBytes > 0 ? Double(bytesReceived) / Double(totalBytes) : 0
        isDownloadPaused = UserDefaults.standard.bool(forKey: pausedDownloadKey)
        if isDownloadPaused { return }
        session.getAllTasks { [weak self] tasks in
            Task { @MainActor in
                guard let self else { return }
                guard let task = tasks.compactMap({ $0 as? URLSessionDownloadTask }).first else {
                    self.clearActiveDownload()
                    return
                }
                self.activeTask = task
                self.activeTaskIdentifier = task.taskIdentifier
                task.taskDescription = model.id
            }
        }
    }

    private func handleProgress(taskID: Int, received: Int64, total: Int64) {
        guard taskID == activeTaskIdentifier else { return }
        bytesReceived = received
        totalBytes = total > 0 ? total : totalBytes
        progress = totalBytes > 0 ? Double(received) / Double(totalBytes) : 0
    }

    private func handleFinished(taskID: Int, result: ModelDownloadCompletion) {
        guard taskID == activeTaskIdentifier else { return }
        switch result {
        case .success(let stableURL):
            finishedURLs[taskID] = stableURL
            if completedTaskIDs.contains(taskID) { beginValidation(taskID: taskID, temporary: stableURL) }
        case .failure(let message):
            failDownload(taskID: taskID, message: message)
        }
    }

    private func handleCompleted(taskID: Int, error: Error?) {
        guard taskID == activeTaskIdentifier else { return }
        if pausingTaskIDs.contains(taskID) { return }
        if let error {
            if (error as? URLError)?.code == .cancelled { clearActiveDownload(); return }
            failDownload(taskID: taskID, error: error)
            return
        }
        completedTaskIDs.insert(taskID)
        if let temporary = finishedURLs[taskID] { beginValidation(taskID: taskID, temporary: temporary) }
    }

    private func finishPause(taskID: Int, modelID: String, resumeData: Data?) {
        guard pausingTaskIDs.remove(taskID) != nil,
              activeTaskIdentifier == taskID else { return }
        guard let resumeData, !resumeData.isEmpty else {
            isDownloadPaused = false
            failDownload(taskID: taskID, message: "O download não pôde ser pausado com segurança.")
            return
        }
        do {
            try resumeData.write(to: resumeDataURL(for: modelID), options: .atomic)
            activeTask = nil
            activeTaskIdentifier = nil
            completedTaskIDs.remove(taskID)
            finishedURLs[taskID] = nil
            UserDefaults.standard.set(true, forKey: pausedDownloadKey)
            UserDefaults.standard.set(bytesReceived, forKey: savedBytesKey)
            UserDefaults.standard.set(totalBytes, forKey: savedTotalBytesKey)
        } catch {
            isDownloadPaused = false
            failDownload(taskID: taskID, message: "Não foi possível salvar a pausa: \(error.localizedDescription)")
        }
    }

    private func beginValidation(taskID: Int, temporary: URL) {
        guard validationTasks[taskID] == nil,
              let model = models.first(where: { $0.id == downloadingModelID }) else { return }
        validationTasks[taskID] = Task { [weak self] in
            do {
                let directory = try self?.modelsDirectory()
                guard let directory else { throw ModelDownloadError.missingDownload }
                try await Task.detached(priority: .utility) {
                    try Self.validateAndInstall(model: model, temporary: temporary, directory: directory)
                }.value
                guard !Task.isCancelled else { return }
                self?.finishDownload(taskID: taskID, modelID: model.id)
            } catch is CancellationError {
                self?.clearActiveDownload()
            } catch {
                self?.failDownload(taskID: taskID, error: error)
            }
        }
    }

    private func finishDownload(taskID: Int, modelID: String) {
        installedModelIDs.insert(modelID)
        validationTasks[taskID] = nil
        clearActiveDownload()
    }

    private func failDownload(taskID: Int, error: Error) {
        if let temporary = finishedURLs[taskID] { try? FileManager.default.removeItem(at: temporary) }
        validationTasks[taskID] = nil
        failDownload(taskID: taskID, message: error.localizedDescription)
    }

    private func failDownload(taskID: Int, message: String) {
        if let temporary = finishedURLs[taskID] { try? FileManager.default.removeItem(at: temporary) }
        validationTasks[taskID] = nil
        errorMessage = message
        clearActiveDownload()
    }

    private func clearActiveDownload() {
        let modelID = downloadingModelID ?? UserDefaults.standard.string(forKey: Self.activeDownloadKey)
        if let id = activeTaskIdentifier {
            finishedURLs[id].map { try? FileManager.default.removeItem(at: $0) }
            finishedURLs[id] = nil
            completedTaskIDs.remove(id)
            validationTasks[id]?.cancel()
            validationTasks[id] = nil
        }
        pausingTaskIDs.removeAll()
        if let modelID { try? FileManager.default.removeItem(at: resumeDataURL(for: modelID)) }
        activeTask = nil
        activeTaskIdentifier = nil
        downloadingModelID = nil
        isDownloadPaused = false
        progress = 0
        bytesReceived = 0
        totalBytes = 0
        UserDefaults.standard.removeObject(forKey: Self.activeDownloadKey)
        UserDefaults.standard.removeObject(forKey: pausedDownloadKey)
        UserDefaults.standard.removeObject(forKey: savedBytesKey)
        UserDefaults.standard.removeObject(forKey: savedTotalBytesKey)
    }

    private func finishBackgroundEvents() {
        backgroundCompletionHandler?()
        backgroundCompletionHandler = nil
    }

    private func modelsDirectory() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = base.appendingPathComponent("Flint/Models", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func temporaryURL(for modelID: String) throws -> URL {
        try modelsDirectory().appendingPathComponent(".\(modelID.replacingOccurrences(of: "/", with: "-"))-download", isDirectory: false)
    }

    private func resumeDataURL(for modelID: String) throws -> URL {
        try modelsDirectory().appendingPathComponent(".\(modelID.replacingOccurrences(of: "/", with: "-"))-resume", isDirectory: false)
    }

    private func refreshInstalledModels() {
        guard let directory = try? modelsDirectory() else { return }
        installedModelIDs = Set(models.compactMap { model in
            FileManager.default.fileExists(atPath: directory.appendingPathComponent(model.fileName).path) ? model.id : nil
        })
    }

    nonisolated private static func validateAndInstall(model: AIModelDescriptor, temporary: URL, directory: URL) throws {
        guard FileManager.default.fileExists(atPath: temporary.path) else { throw ModelDownloadError.missingDownload }
        let attributes = try FileManager.default.attributesOfItem(atPath: temporary.path)
        guard let size = attributes[.size] as? NSNumber, size.int64Value == model.expectedBytes else {
            throw ModelDownloadError.invalidSize
        }
        let checksum = try sha256(of: temporary)
        guard checksum == model.sha256 else { throw ModelDownloadError.invalidChecksum }
        let destination = directory.appendingPathComponent(model.fileName, isDirectory: false)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporary, to: destination)
    }

    nonisolated private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

private final class ModelDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Int, Int64, Int64) -> Void
    private let onFinished: @Sendable (Int, ModelDownloadCompletion) -> Void
    private let onCompleted: @Sendable (Int, Error?) -> Void
    private let onEventsFinished: @Sendable () -> Void

    init(
        onProgress: @escaping @Sendable (Int, Int64, Int64) -> Void,
        onFinished: @escaping @Sendable (Int, ModelDownloadCompletion) -> Void,
        onCompleted: @escaping @Sendable (Int, Error?) -> Void,
        onEventsFinished: @escaping @Sendable () -> Void
    ) {
        self.onProgress = onProgress; self.onFinished = onFinished
        self.onCompleted = onCompleted; self.onEventsFinished = onEventsFinished
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        onProgress(downloadTask.taskIdentifier, totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let taskID = downloadTask.taskIdentifier
        guard let response = downloadTask.response as? HTTPURLResponse,
              (200...299).contains(response.statusCode) else {
            try? FileManager.default.removeItem(at: location)
            let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? -1
            onFinished(taskID, .failure(ModelDownloadError.httpStatus(status).localizedDescription))
            return
        }

        guard let modelID = downloadTask.taskDescription
            ?? UserDefaults.standard.string(forKey: ModelStore.activeDownloadKey),
            let model = AIModelCatalog.recommended.first(where: { $0.id == modelID }),
            let directory = try? Self.modelsDirectory(),
            let destination = try? Self.temporaryURL(for: model, directory: directory) else {
            try? FileManager.default.removeItem(at: location)
            onFinished(taskID, .failure(ModelDownloadError.missingDownload.localizedDescription))
            return
        }

        do {
            try? FileManager.default.removeItem(at: destination)
            // URLSession owns this temporary URL only until this delegate method
            // returns. Move it synchronously before notifying the MainActor.
            try FileManager.default.moveItem(at: location, to: destination)
            onFinished(taskID, .success(destination))
        } catch {
            try? FileManager.default.removeItem(at: location)
            onFinished(taskID, .failure(ModelDownloadError.moveFailed(error.localizedDescription).localizedDescription))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        onCompleted(task.taskIdentifier, error)
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) { onEventsFinished() }

    private static func modelsDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("Flint/Models", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func temporaryURL(for model: AIModelDescriptor, directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(
            ".\(model.id.replacingOccurrences(of: "/", with: "-"))-download",
            isDirectory: false
        )
        return url
    }
}
