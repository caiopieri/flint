import Foundation

/// Formato em disco de um arquivo `.ink`: um wrapper JSON em volta de um desenho
/// PencilKit + o template de papel. Um arquivo = um desenho (escopo travado).
/// Tipo puro e Sendable - sem dependencia de PencilKit, para ser unit-testavel.
struct InkDocument: Codable, Equatable, Sendable {
    enum Paper: String, Codable, CaseIterable, Sendable {
        case blank, lined, grid, dotted
    }

    var paper: Paper
    /// Bytes de `PKDrawing.dataRepresentation()`. Opacos aqui de proposito.
    var drawingData: Data

    init(paper: Paper = .dotted, drawingData: Data = Data()) {
        self.paper = paper
        self.drawingData = drawingData
    }

    /// Decodifica de bytes de arquivo. `Data` vazia -> documento default (arquivo recem-criado).
    static func decode(_ data: Data) throws -> InkDocument {
        guard !data.isEmpty else { return InkDocument() }
        return try JSONDecoder().decode(InkDocument.self, from: data)
    }

    /// Serializa para gravar em disco.
    func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }
}
