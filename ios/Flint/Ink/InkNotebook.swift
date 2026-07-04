import Foundation

/// Formato em disco de um `.ink`: um caderno de paginas PencilKit + papel por
/// pagina, serializado em JSON. Tipo puro e Sendable (sem PencilKit) -> testavel.
struct InkNotebook: Codable, Equatable, Sendable {
    enum Paper: String, Codable, CaseIterable, Sendable { case blank, lined, grid, dotted }

    struct Page: Codable, Equatable, Sendable, Identifiable {
        var id: UUID
        var paper: Paper
        /// Bytes de `PKDrawing.dataRepresentation()`. Opacos aqui de proposito.
        var drawingData: Data

        init(id: UUID = UUID(), paper: Paper = .dotted, drawingData: Data = Data()) {
            self.id = id
            self.paper = paper
            self.drawingData = drawingData
        }
    }

    /// Invariante mantida pelos chamadores (UI): sempre >= 1 pagina.
    var pages: [Page]

    init(pages: [Page] = [Page()]) {
        self.pages = pages
    }

    /// `Data` vazia -> caderno default (1 pagina em branco). Nao lanca nesse caso.
    static func decode(_ data: Data) throws -> InkNotebook {
        guard !data.isEmpty else { return InkNotebook() }
        return try JSONDecoder().decode(InkNotebook.self, from: data)
    }

    func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }
}
