//
//  gir.swift
//  Gtk3Swift
//
//  Created by Rene Hexel on 25/03/2016.
//  Copyright © 2016 Rene Hexel. All rights reserved.
//
#if os(Linux)
    import GLibc
#else
    import Darwin
#endif

extension String {
    var withoutNameSpace: String {
        let chars = characters
        guard let dot = chars.enumerate().filter({ $0.1 == "." }).last else {
            return self
        }
        return String(chars[chars.startIndex.advancedBy(dot.index+1)..<chars.endIndex])
    }
}


public class GIR {
    public let xml: XMLDocument
    public var preamble = ""
    public var prefix = ""
    public var identifierPrefixes = Array<String>()
    public var symbolPrefixes = Array<String>()
    public var namespaces: AnySequence<XMLNameSpace> = emptySequence()
    public var aliases: [Alias] = []
    public var constants: [Constant] = []
    public var enumerations: [Enumeration] = []
    public var bitfields: [Bitfield] = []
    public var records: [Record] = []
    public var classes: [Class] = []

    /// names of black-listed identifiers
    static var Blacklist: Set<String> = []

    /// names of constants to be taken verbatim
    static var VerbatimConstants: Set<String> = []

    /// context of known types
    static var KnownTypes:   [ String : Type ] = [:]
    static var KnownRecords: [ String : Type ] = [:]
    static var GErrorType = "GErrorType"

    /// designated constructor
    public init(xmlDocument: XMLDocument) {
        xml = xmlDocument
        if let rp = xml.findFirstWhere({ $0.name == "repository" }) {
            namespaces = rp.namespaces
//            for n in namespaces {
//                print("Got \(n.prefix) at \(n.href)")
//            }
        }
        //
        // set up name space prefix
        //
        if let ns = xml.xpath("//gir:namespace", namespaces: namespaces, defaultPrefix: "gir")?.generate().next() {
            if let name = ns.attribute("name") {
                prefix = name
            }
            identifierPrefixes = ns.sortedSubAttributesFor("identifier-prefixes")
            symbolPrefixes     = ns.sortedSubAttributesFor("symbol-prefixes")
        }
        //
        // get all type alias records
        //
        if let entries = xml.xpath("/*/*/gir:alias", namespaces: namespaces, defaultPrefix: "gir") {
            aliases = entries.enumerate().map { Alias(node: $0.1, atIndex: $0.0) }.filter {
                let name = $0.node
                guard GIR.KnownTypes[name] == nil else {
                    fputs("Warning: duplicate type '\(name)' for alias ignored!\n", stderr)
                    return false
                }
                GIR.KnownTypes[name] = $0
                return true
            }
        }
        //
        // get all constants
        //
        if let entries = xml.xpath("/*/*/gir:constant", namespaces: namespaces, defaultPrefix: "gir") {
            constants = entries.enumerate().map { Constant(node: $0.1, atIndex: $0.0) }.filter {
                let name = $0.node
                guard GIR.KnownTypes[name] == nil else {
                    fputs("Warning: duplicate type '\(name)' for constant ignored!\n", stderr)
                    return false
                }
                GIR.KnownTypes[name] = $0
                return true
            }
        }
        //
        // get all enums
        //
        if let entries = xml.xpath("/*/*/gir:enumeration", namespaces: namespaces, defaultPrefix: "gir") {
            enumerations = entries.enumerate().map { Enumeration(node: $0.1, atIndex: $0.0) }.filter {
                let name = $0.node
                guard GIR.KnownTypes[name] == nil else {
                    fputs("Warning: duplicate type '\(name)' for enum ignored!\n", stderr)
                    return false
                }
                GIR.KnownTypes[name] = $0
                return true
            }
        }
        //
        // get all type records
        //
        if let recs = xml.xpath("/*/*/gir:record", namespaces: namespaces, defaultPrefix: "gir") {
            records = recs.enumerate().map { Record(node: $0.1, atIndex: $0.0) }.filter {
                let name = $0.node
                guard GIR.KnownTypes[name] == nil else {
                    fputs("Warning: duplicate type '\(name)' for record ignored!\n", stderr)
                    return false
                }
                GIR.KnownTypes[name] = $0
                GIR.KnownRecords[name] = $0
                return true
            }
        }
        //
        // get all class records
        //
        if let recs = xml.xpath("/*/*/gir:class", namespaces: namespaces, defaultPrefix: "gir") {
            classes = recs.enumerate().map { Class(node: $0.1, atIndex: $0.0) }.filter {
                let name = $0.node
                guard GIR.KnownTypes[name] == nil else {
                    fputs("Warning: duplicate type '\(name)' for class ignored!\n", stderr)
                    return false
                }
                GIR.KnownTypes[name] = $0
                GIR.KnownRecords[name] = $0
                return true
            }
        }
    }

    /// convenience constructor to read a gir file
    public convenience init?(fromFile name: String) {
        guard let xml = XMLDocument(fromFile: name) else { return nil }
        self.init(xmlDocument: xml)
    }

    /// convenience constructor to read from memory
    public convenience init?(buffer content: UnsafeBufferPointer<CChar>) {
        guard let xml = XMLDocument(buffer: content) else { return nil }
        self.init(xmlDocument: xml)
    }


    /// GIR named thing class
    public class Thing {
        public let name: String             ///< type name without namespace/prefix
        public let comment: String          ///< documentation
        public let introspectable: Bool     ///< is this thing introspectable?
        public let deprecated: String?      ///< alternative to use if deprecated
        public let markedAsDeprecated: Bool ///< explicitly marked as deprecated
        public let version: String?         ///< availability in given version

        public init(name: String, comment: String, introspectable: Bool = false, deprecated: String? = nil, markedAsDeprecated: Bool = false, version: String? = nil) {
            self.name = name
            self.comment = comment
            self.introspectable = introspectable
            self.deprecated = deprecated
            self.markedAsDeprecated = markedAsDeprecated
            self.version = version
        }

        public init(node: XMLElement, atIndex i: Int, nameAttr: String = "name") {
            name = node.attribute(nameAttr) ?? "Unknown\(i)"
            let children = node.children.lazy
            let depr = node.bool("deprecated")
            comment = GIR.docs(children)
            markedAsDeprecated = depr
            deprecated = GIR.deprecatedDocumentation(children) ?? ( depr ? "This method is deprecated." : nil )
            introspectable = node.bool("introspectable")
            version = node.attribute("version")
        }
    }


    /// GIR type class
    public class Type: Thing {
        public let type: String         ///< C typedef name

        public init(name: String, type: String, comment: String, introspectable: Bool = false, deprecated: String? = nil) {
            self.type = type
            super.init(name: name, comment: comment, introspectable: introspectable, deprecated: deprecated)
        }

        public init(node: XMLElement, atIndex i: Int, nameAttr: String = "name", typeAttr: String = "type") {
            type = node.attribute(typeAttr) ?? ""
            super.init(node: node, atIndex: i, nameAttr: nameAttr)

            // handle the magic error type
            if name == errorType { GErrorType = type.swift }
        }

        public init(node: XMLElement, atIndex i: Int, withType t: String, nameAttr: String = "name") {
            type = t
            super.init(node: node, atIndex: i, nameAttr: nameAttr)

            // handle the magic error type
            if name == errorType { GErrorType = type.swift }
        }

        public var isVoid: Bool {
            return type.hasPrefix("Void") || type.hasPrefix("void")
        }
    }


    /// a type with an underlying C type entry
    public class CType: Type {
        public let ctype: String            ///< underlying C type
        public let containedTypes: [CType]  ///< list of contained types

        /// designated initialiser
        public init(name: String, type: String, ctype: String, comment: String, introspectable: Bool = false, deprecated: String? = nil, contains: [CType] = []) {
            self.ctype = ctype
            self.containedTypes = contains
            super.init(name: name, type: type, comment: comment, introspectable: introspectable, deprecated: deprecated)
        }

        /// factory method to construct an alias from XML
        public init(node: XMLElement, atIndex i: Int, nameAttr: String = "name", typeAttr: String = "type", cTypeAttr: String? = nil) {
            containedTypes = node.children.filter { $0.name == "type" }.map { CType(node: $0, atIndex: i, cTypeAttr: "type") }
            if let cta = cTypeAttr {
                ctype = node.attribute(cta) ?? "Void /* unknown \(i) */"
            } else {
                if node.name == "array" {
                    ctype = node.attribute("type") ?? "Void /* unknown \(i) */"
                } else {
                    let children = node.children.lazy
                    var types = children.filter { $0.name == "type" }.generate()
                    if let typeEntry = types.next() {
                        ctype = typeEntry.attribute("name") ?? (typeEntry.attribute("type") ?? "Void /* unknown type \(i) */")
                    } else {
                        ctype = "Void /* unknown type \(i) */"
                    }
                }
            }
            super.init(node: node, atIndex: i, nameAttr: nameAttr, typeAttr: typeAttr)
        }

        /// factory method to construct an alias from XML with types taken from children
        public init(fromChildrenOf node: XMLElement, atIndex i: Int, nameAttr: String = "name", typeAttr: String = "type") {
            let type: String
            let ctype: String
            if let array = node.children.lazy.filter({ $0.name == "array" }).first {
                containedTypes = array.children.filter { $0.name == "type" }.map { CType(node: $0, atIndex: i, cTypeAttr: "type") }
                ctype = array.attribute("type") ?? "Void /* unknown ctype \(i) */"
                type  = array.attribute("name") ?? ctype
            } else {
                containedTypes = []
                (type, ctype) = GIR.types(node, at: i)
            }
            self.ctype = ctype
            super.init(node: node, atIndex: i, withType: type, nameAttr: nameAttr)
        }

        /// return whether the give C type is void
        override public var isVoid: Bool {
            let t = ctype.isEmpty ? type.swift : toSwift(ctype)
            return t.hasPrefix("Void")
        }

        /// return whether the type is an array
        public var isArray: Bool { return !containedTypes.isEmpty }
    }

    /// a type alias is just a type with an underlying C type
    public typealias Alias = CType


    /// an entry for a constant
    public class Constant: CType {
        public let value: Int           ///< raw value

        public init(name: String, type: String, ctype: String, value: Int, comment: String, introspectable: Bool = false, deprecated: String? = nil) {
            self.value = value
            super.init(name: name, type: type, ctype: ctype, comment: comment, introspectable: introspectable, deprecated: deprecated)
        }

        /// factory method to construct a constant from XML
        public override init(node: XMLElement, atIndex i: Int, nameAttr: String = "name", typeAttr: String = "type", cTypeAttr: String? = nil) {
            if let val = node.attribute("value"), let v = Int(val) {
                value = v
            } else {
                value = i
            }
            super.init(node: node, atIndex: i, nameAttr: nameAttr, typeAttr: typeAttr, cTypeAttr: cTypeAttr)
        }
    }


    /// an enumeration entry
    public class Enumeration: Type {
        /// an enumeration value is a constant
        public typealias Member = Constant

        /// enumeration values
        public let members: [Member]

        public init(name: String, type: String, members: [Member], comment: String, introspectable: Bool = false, deprecated: String? = nil) {
            self.members = members
            super.init(name: name, type: type, comment: comment, introspectable: introspectable, deprecated: deprecated)
        }

        /// factory method to construct an enumeration entry from XML
        public init(node: XMLElement, atIndex i: Int) {
            let mem = node.children.lazy.filter { $0.name == "member" }
            members = mem.enumerate().map { Member(node: $0.1, atIndex: $0.0, cTypeAttr: "identifier") }
            super.init(node: node, atIndex: i)
        }
    }

    /// a bitfield is an enumeration
    public typealias Bitfield = Enumeration


    /// a data type record to create a protocol/struct/class for
    public class Record: CType {
        public let cprefix: String          ///< C language symbol prefix
        public let typegetter: String       ///< C type getter function
        public let methods: [Method]        ///< all associated methods
        public let functions: [Function]    ///< all associated functions
        public let constructors: [Method]   ///< list of constructors

        /// designated constructor
        public init(name: String, type: String, ctype: String, cprefix: String, typegetter: String, methods: [Method] = [], functions: [Function] = [], constructors: [Method] = [], comment: String = "", introspectable: Bool = false, deprecated: String? = nil) {
            self.cprefix = cprefix
            self.typegetter = typegetter
            self.methods = methods
            self.functions = functions
            self.constructors = constructors
            super.init(name: name, type: type, ctype: ctype, comment: comment, introspectable: introspectable, deprecated: deprecated)
        }

        /// XML constructor
        public init(node: XMLElement, atIndex i: Int) {
            cprefix = node.attribute("symbol-prefix") ?? ""
            typegetter = node.attribute("get-type") ?? ""
            let children = node.children.lazy
            let funcs = children.filter { $0.name == "function" }
            functions = funcs.enumerate().map { Function(node: $0.1, atIndex: $0.0) }
            let meths = children.filter { $0.name == "method" }
            methods = meths.enumerate().map { Method(node: $0.1, atIndex: $0.0) }
            let cons = children.filter { $0.name == "constructor" }
            constructors = cons.enumerate().map { Method(node: $0.1, atIndex: $0.0) }
            super.init(node: node, atIndex: i, typeAttr: "type-name", cTypeAttr: "type")
        }
    }

    /// a class data type record
    public class Class: Record {
        public let parent: String           ///< parent class name

        override init(node: XMLElement, atIndex i: Int) {
            parent = node.attribute("parent") ?? ""
            super.init(node: node, atIndex: i)
        }
    }


    /// data type representing a function/method
    public class Method: Thing {
        public let cname: String        ///< original C function name
        public let returns: Argument    ///< C language type name
        public let args: [Argument]     ///< all associated methods
        public let throwsError: Bool    ///< does this method throw an error?

        /// designated constructor
        public init(name: String, cname: String, returns: Argument, args: [Argument] = [], comment: String = "", introspectable: Bool = false, deprecated: String? = nil, throwsAnError: Bool = false) {
            self.cname = cname
            self.returns = returns
            self.args = args
            throwsError = throwsAnError
            super.init(name: name, comment: comment, introspectable: introspectable, deprecated: deprecated)
        }

        /// XML constructor
        public init(node: XMLElement, atIndex i: Int) {
            cname = node.attribute("identifier") ?? ""
            let thrAttr = node.attribute("throws") ?? "0"
            throwsError = (Int(thrAttr) ?? 0) != 0
            let children = node.children.lazy
            if let ret = children.findFirstWhere({ $0.name == "return-value"}) {
                let arg = Argument(node: ret, atIndex: -1)
                returns = arg
            } else {
                returns = Argument(name: "", type: "Void", ctype: "void", instance: false, comment: "")
            }
            if let params = children.findFirstWhere({ $0.name == "parameters"}) {
                let children = params.children.lazy
                args = GIR.args(children)
            } else {
                args = GIR.args(children)
            }
            super.init(node: node, atIndex: i)
        }

        /// indicate whether this is a varargs method
        public var varargs: Bool {
            return args.lazy.filter({$0.varargs}).first != nil
        }
    }

    /// a function is the same as a method
    public typealias Function = Method


    /// data type representing a function/method argument or return type
    public class Argument: CType {
        public let instance: Bool       ///< is this an instance parameter?
        public let _varargs: Bool       ///< is this a varargs (...) parameter?

        /// indicate whether the given parameter is varargs
        public var varargs: Bool {
            return _varargs || name.hasPrefix("...")
        }

        /// default constructor
        public init(name: String, type: String, ctype: String, instance: Bool, comment: String, introspectable: Bool = false, deprecated: String? = nil, varargs: Bool = false) {
            self.instance = instance
            _varargs = varargs
            super.init(name: name, type: type, ctype: ctype, comment: comment, introspectable: introspectable, deprecated: deprecated)
        }

        /// XML constructor
        public init(node: XMLElement, atIndex i: Int) {
            instance = node.name.hasPrefix("instance")
            _varargs = node.children.lazy.findFirstWhere({ $0.name == "varargs"}) != nil
            super.init(fromChildrenOf: node, atIndex: i)
        }
    }
}

/// some utility methods for things
public extension GIR.Thing {
    /// type name without 'Private' suffix (nil if public)
    public var priv: String? {
        return name.stringByRemoving(suffix: "Private")
    }
    /// Type name without 'Class', 'Iface', etc. suffix
    public var node: String {
        let nodeName: String
        let privateSuffix: String
        if let p = priv {
            nodeName = p
            privateSuffix = "Private"
        } else {
            nodeName = name
            privateSuffix = ""
        }
        for s in ["Class", "Iface"] {
            if let n = nodeName.stringByRemoving(suffix: s) {
                return n + privateSuffix
            }
        }
        return name
    }
}

/// helper context class for tree traversal
class ConversionContext {
    let level: Int
    let parent: ConversionContext?
    let parentNode: XMLTree.Node!
    let conversion: [String : XMLTree.Node -> String]
    var outputs: [String] = []

    init(_ conversion: [String : XMLTree.Node -> String] = [:], level: Int = 0, parent: ConversionContext? = nil, parentNode: XMLTree.Node? = nil) {
        self.level = level
        self.parent = parent
        self.parentNode = parentNode
        self.conversion = conversion
    }

    /// push a context
    func push(node: XMLTree.Node, _ fs: [String : XMLTree.Node -> String]) -> ConversionContext {
        return ConversionContext(fs, level: node.level+1, parent: self, parentNode: node)
    }
}

private func indent(level: Int, _ s: String = "") -> String {
    return String(count: level * 4, repeatedValue: Character(" ")) + s
}

extension GIR {
    ///
    /// return the documentation for the given child nodes
    ///
    public class func docs(children: LazySequence<AnySequence<XMLElement>>) -> String {
        return documentation("doc", children: children)
    }

    ///
    /// return the documentation for the given child nodes
    ///
    public class func deprecatedDocumentation(children: LazySequence<AnySequence<XMLElement>>) -> String? {
        let doc = documentation("doc-deprecated", children: children)
        guard !doc.isEmpty else { return nil }
        return doc
    }

    ///
    /// return the documentation for the given child nodes
    ///
    public class func documentation(name: String, children: LazySequence<AnySequence<XMLElement>>) -> String {
        let docs = children.filter { $0.name == name }
        let comments = docs.map { $0.content}
        return comments.joinWithSeparator("\n")
    }

    ///
    /// return the method/function arguments for the given child nodes
    ///
    public class func args(children: LazySequence<AnySequence<XMLElement>>) -> [Argument] {
        let parameters = children.filter { $0.name.hasSuffix("parameter") }
        let args = parameters.enumerate().map { Argument(node: $1, atIndex: $0) }
        return args
    }

    ///
    /// return the array / type information of an argument or return type node
    ///
    class func types(node: XMLElement, at i: Int) -> (type: String, ctype: String) {
        for child in node.children {
            let type = child.attribute("name") ?? (child.attribute("type") ?? "Void /* unknown type \(i) */")
            let t: XMLElement
            if child.name == "type" { t = child }
            else if let at = child.children.filter({ $0.name == "type" }).first {
                t = at
            } else { continue }
            let ctype = t.attribute("type") ?? (t.attribute("name") ?? "void /* untyped argument \(i)")
            return (type: type, ctype: ctype)
        }
        return (type: "Void /* missing type \(i) */", ctype: "void /* missing C type \(i)")
    }

    ///
    /// dump Swift code
    ///
    public func dumpSwift() -> String {
        var context = ConversionContext([:])
        context = ConversionContext(["repository": {
            let s = indent($0.level, "// \($0.node.name) @ \($0.level)+\(context.level)")
            context = context.push($0, ["namespace": {
                let s = indent($0.level, "// \($0.node.name) @ \($0.level)+\(context.level)")
                context = context.push($0, ["alias": {
                    context = context.push($0, ["type": {
                        if let type  = $0.node.attribute("name"),
                           let alias = context.parentNode.node.attribute("name") where !alias.isEmpty && !type.isEmpty {
                            context.outputs = ["public typealias \(alias) = \(type)"]
                        } else {
                            context.outputs = ["// error alias \($0.node.attribute("name")) = \(context.parentNode.node.attribute("name"))"]
                        }
                        return ""
                        }])
                    return s
                }, "function": {
                    let s: String
                    if let name = $0.node.attribute("name") where !name.isEmpty {
                        s = "func \(name)("
                    } else { s = "// empty function " }
                    context = context.push($0, ["type": {
                        if let type  = $0.node.attribute("name"),
                            let alias = context.parentNode.node.attribute("name") where !alias.isEmpty && !type.isEmpty {
                            context.outputs = ["public typealias \(alias) = \(type)"]
                        } else {
                            context.outputs = ["// error alias \($0.node.attribute("name")) = \(context.parentNode.node.attribute("name"))"]
                        }
                        return ""
                        }])
                    return s
                }])
                return s
            }])
            return s
        }])
        return (xml.tree.map { (tn: XMLTree.Node) -> String in
            if let f = context.conversion[tn.node.name] { return f(tn) }
            while context.level > tn.level {
                if let parent = context.parent { context = parent }
                else { assert(context.level == 0) }
            }
            return indent(tn.level, "// unhandled: \(tn.node.name) @ \(tn.level)+\(context.level)")
            }).reduce("") { (output: String, element: String) -> String in
                output + "\(element)\n"
        }
    }
}

extension XMLElement {
    ///
    /// return an attribute as a list of sub-attributeds split by a given character
    /// and ordered with the longest attribute name first
    ///
    public func sortedSubAttributesFor(attr: String, splitBy char: Character = ",", orderedBy: (String, String) -> Bool = { $0.characters.count > $1.characters.count || ($0.characters.count == $1.characters.count && $0 < $1)}) -> [String] {
        guard let attrs = ((attribute(attr)?.characters)?.split(char))?.map(String.init) else { return [] }
        return attrs.sort(orderedBy)
    }

    ///
    /// return the documentation for a given node
    ///
    public func docs() -> String {
        return GIR.docs(children.lazy)
    }
}
