import Cocoa

/// Feature-specific metadata and remembered hints; raw AX reads stay generic.
extension AccessibilityElement {
    var rememberedMinimumSize: CGSize? {
        WindowSizeConstraints.shared.rememberedMinimum(for: self)
    }

    var sizeConstraintIdentity: (identifier: String?, role: String, subrole: String, structure: [String]) {
        let identifier = axElement.getValue(.identifier) as? String
        let subrole = axElement.getValue(.subrole) as? String ?? ""
        let children = childElements
        let structure: [String]
        if let children, !children.isEmpty, children.count <= 32 {
            structure = children.map {
                [$0.role?.rawValue ?? "", $0.axElement.getValue(.subrole) as? String ?? "",
                 $0.axElement.getValue(.identifier) as? String ?? ""].joined(separator: "|")
            }.sorted()
        } else { structure = [] }
        return (identifier, role?.rawValue ?? "", subrole, structure)
    }
}
