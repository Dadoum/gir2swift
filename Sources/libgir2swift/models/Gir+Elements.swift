//
//  File.swift
//  
//
//  Created by Mikoláš Stuchlík on 17.11.2020.
//
#if os(Linux)
    import Glibc
#else
    import Darwin
#endif
import SwiftLibXML

extension GIR {
    /// GIR named thing class
    public class Thing: Hashable, Comparable {
        /// String representation of the kind of `Thing` represented by the receiver
        public var kind: String { return "Thing" }
        /// type name without namespace/prefix
        public let name: String
        /// documentation for the `Thing`
        public let comment: String
        /// Is this `Thing` introspectable?
        public let introspectable: Bool
        /// Is this `Thing` disguised?
        public let disguised: Bool
        /// Alternative to use if deprecated
        public let deprecated: String?
        /// Is this `Thing` explicitly marked as deprecated?
        public let markedAsDeprecated: Bool
        /// Version the receiver is available from
        public let version: String?
        
        /// Hashes the essential components of this value by feeding them into the given hasher.
        ///
        /// This method is implemented to conform to the Hashable protocol.
        /// Calls hasher.combine(_:) with the name component.
        /// - Parameter hasher: The hasher to use when combining the components of the receiver.
        public func hash(into hasher: inout Hasher) {
            hasher.combine(name)
        }
        
        
        /// Comparator to check whether two `Thing`s are equal
        /// - Parameters:
        ///   - lhs: `Thing` to compare
        ///   - rhs: `Thing` to compare with
        public static  func ==(lhs: GIR.Thing, rhs: GIR.Thing) -> Bool {
            return lhs.name == rhs.name
        }

        /// Comparator to check the ordering of two `Thing`s
        /// - Parameters:
        ///   - lhs: first `Thing` to compare
        ///   - rhs: second `Thing` to compare
        public static func <(lhs: GIR.Thing, rhs: GIR.Thing) -> Bool {
            return lhs.name < rhs.name
        }
        
        /// type name without 'Private' suffix (nil if public)
        var priv: String? {
            return name.stringByRemoving(suffix: "Private")
        }
        /// Type name without 'Class', 'Iface', etc. suffix
        var node: String {
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
        
        /// Memberwise initialiser
        /// - Parameters:
        ///   - name: The name of the `Thing` to initialise
        ///   - comment: Documentation text for the `Thing`
        ///   - introspectable: Set to `true` if introspectable
        ///   - disguised: Set to `true` if disguised
        ///   - deprecated: Documentation on deprecation status if non-`nil`
        ///   - markedAsDeprecated: Set to `true` if deprecated
        ///   - version: The version this `Thing` is first available in
        public init(name: String, comment: String, introspectable: Bool = true, disguised: Bool = false, deprecated: String? = nil, markedAsDeprecated: Bool = false, version: String? = nil) {
            self.name = name
            self.comment = comment
            self.introspectable = introspectable
            self.disguised = disguised
            self.deprecated = deprecated
            self.markedAsDeprecated = markedAsDeprecated
            self.version = version
        }
        
        /// XML Element initialser
        /// - Parameters:
        ///   - node: `XMLElement` to construct this `Thing` from
        ///   - index: Index within the siblings of the `node`
        ///   - nameAttr: Key for the attribute to extract the `name` property from
        public init(node: XMLElement, at index: Int, nameAttr: String = "name") {
            name = node.attribute(named: nameAttr) ?? "Unknown\(index)"
            let c = node.children.lazy
            let depr = node.bool(named: "deprecated")
            comment = GIR.docs(children: c)
            markedAsDeprecated = depr
            deprecated = GIR.deprecatedDocumentation(children: c) ?? ( depr ? "This method is deprecated." : nil )
            introspectable = (node.attribute(named: "introspectable") ?? "1") != "0"
            disguised = node.bool(named: "disguised")
            version = node.attribute(named: "version")
        }
    }


    /// GIR type class
    public class Datatype: Thing {
        /// String representation of the `Datatype` thing
        public override var kind: String { return "Datatype" }
        /// The underlying type
        public var typeRef: TypeReference
        /// The identifier of this instance (e.g. C enum value type)
        @inlinable public var identifier: String? { typeRef.identifier }

        /// A reference to the underlying C type
        @inlinable public var underlyingCRef: TypeReference {
            let type = typeRef.type
            let nm = typeRef.fullCType
            let tp = GIRType(name: nm, ctype: type.ctype, superType: type.parent, isAlias: type.isAlias, conversions: type.conversions)
            let ref = TypeReference(type: tp, identifier: typeRef.identifier, isConst: typeRef.isConst, isOptional: typeRef.isOptional, isArray: typeRef.isArray, constPointers: typeRef.constPointers)
            return ref
        }

        /// Memberwise initialiser
        /// - Parameters:
        ///   - name: The name of the `Datatype` to initialise
        ///   - type: The corresponding, underlying GIR type
        ///   - comment: Documentation text for the data type
        ///   - introspectable: Set to `true` if introspectable
        ///   - deprecated: Documentation on deprecation status if non-`nil`
        ///   - version: The version this data type is first available in
        public init(name: String, type: TypeReference, comment: String, introspectable: Bool = false, deprecated: String? = nil) {
            typeRef = type
            super.init(name: name, comment: comment, introspectable: introspectable, deprecated: deprecated)
            registerKnownType()
        }

        /// XML Element initialser
        /// - Parameters:
        ///   - node: `XMLElement` to construct this data type from
        ///   - index: Index within the siblings of the `node`
        ///   - type: Type reference for the data type (taken from XML if `nil`)
        ///   - nameAttr: Key for the attribute to extract the `name` property from
        public init(node: XMLElement, at index: Int, with type: TypeReference? = nil, nameAttr: String = "name") {
            typeRef = type ?? node.alias
            super.init(node: node, at: index, nameAttr: nameAttr)
            typeRef.isArray = node.name == "array"
            registerKnownType()
        }

        /// Register this type as an enumeration type
        @inlinable
        public func registerKnownType() {
        }

        /// Returns `true` if the data type is `void`
        public var isVoid: Bool {
            return typeRef.isVoid
        }
    }


    /// a type with an underlying C type entry
    public class CType: Datatype {
        /// String representation of the `CType` thing
        public override var kind: String { return "CType" }
        /// list of contained types
        public let containedTypes: [CType]
        /// reference scope
        public let scope: String?
        /// `true` if this is a readable element
        public let isReadable: Bool
        /// `true` if this is a writable element
        public let isWritable: Bool
        /// `true` if this is a private element
        public let isPrivate: Bool
        /// tuple size if non-`nil`
        public let tupleSize: Int?

        /// Returns `true` if the data type is `void`
        public override var isVoid: Bool {
            return super.isVoid && (tupleSize ?? 0) == 0
        }

        /// Designated initialiser
        /// - Parameters:
        ///   - name: The name of the `Datatype` to initialise
        ///   - type: The corresponding, underlying GIR type
        ///   - comment: Documentation text for the data type
        ///   - introspectable: Set to `true` if introspectable
        ///   - deprecated: Documentation on deprecation status if non-`nil`
        ///   - isWritable: Set to `true` if this is a writable type
        ///   - contains: Array of C types contained within this type
        ///   - tupleSize: Size of the given tuple if non-`nil`
        ///   - scope: The scope this type belongs in
        public init(name: String, type: TypeReference, comment: String, introspectable: Bool = false, deprecated: String? = nil, isPrivate: Bool = false, isReadable: Bool = true, isWritable: Bool = false, contains: [CType] = [], tupleSize: Int? = nil, scope: String? = nil) {
            self.isPrivate  = isPrivate
            self.isReadable = isReadable
            self.isWritable = isWritable
            self.containedTypes = contains
            self.tupleSize = tupleSize
            self.scope = scope
            super.init(name: name, type: type, comment: comment, introspectable: introspectable, deprecated: deprecated)
        }

        /// XML Element initialser
        /// - Parameters:
        ///   - node: `XMLElement` to construct this C type from
        ///   - index: Index within the siblings of the `node`
        ///   - nameAttr: Key for the attribute to extract the `name` property from
        ///   - privateAttr:  Key for the attribute to extract the privacy status from
        ///   - readableAttr: Key for the attribute to extract the readbility status from
        ///   - writableAttr: Key for the attribute to extract the writability status from
        ///   - scopeAttr: Key for the attribute to extract the  scope string from
        public init(node: XMLElement, at index: Int, nameAttr: String = "name", privateAttr: String = "private", readableAttr: String = "readable", writableAttr: String = "writable", scopeAttr: String = "scope") {
            containedTypes = node.containedTypes
            isPrivate  = node.attribute(named: privateAttr) .flatMap({ Int($0) }).map({ $0 != 0 }) ?? false
            isReadable = node.attribute(named: readableAttr).flatMap({ Int($0) }).map({ $0 != 0 }) ?? true
            isWritable = node.attribute(named: writableAttr).flatMap({ Int($0) }).map({ $0 != 0 }) ?? false
            tupleSize = node.attribute(named: "fixed-size").flatMap(Int.init)
            scope = node.attribute(named: scopeAttr)
            super.init(node: node, at: index, nameAttr: nameAttr)
        }

        /// Factory method to construct a C Type from XML with types taken from children
        /// - Parameters:
        ///   - node: `XMLElement` whose descendants to construct this C type from
        ///   - index: Index within the siblings of the `node`
        ///   - nameAttr: Key for the attribute to extract the `name` property from
        ///   - typeAttr: Key for the attribute to extract the `type` property from
        ///   - scopeAttr: Key for the attribute to extract the  scope string from
        public init(fromChildrenOf node: XMLElement, at index: Int, nameAttr: String = "name", privateAttr: String = "private", readableAttr: String = "readable", writableAttr: String = "writable", scopeAttr: String = "scope") {
            let type: TypeReference
            isPrivate  = node.attribute(named: privateAttr) .flatMap({ Int($0) }).map({ $0 != 0 }) ?? false
            isReadable = node.attribute(named: readableAttr).flatMap({ Int($0) }).map({ $0 != 0 }) ?? true
            isWritable = node.attribute(named: writableAttr).flatMap({ Int($0) }).map({ $0 != 0 }) ?? false
            scope = node.attribute(named: scopeAttr)
            if let array = node.children.filter({ $0.name == "array" }).first {
                type = array.alias
                tupleSize = array.attribute(named: "fixed-size").flatMap(Int.init)
                containedTypes = array.containedTypes
            } else {
                containedTypes = []
                tupleSize = nil
                type = GIR.typeOf(node: node)
            }
            super.init(node: node, at: index, with: type, nameAttr: nameAttr)
        }

        /// return whether the type is an array
        @inlinable
        public var isArray: Bool { return !containedTypes.isEmpty }

        /// return whether the receiver is an instance of the given record (class)
        /// - Parameter record: The record to test for
        /// - Returns: `true` if `self` points to `record`
        @inlinable
        public func isInstanceOf(_ record: GIR.Record?) -> Bool {
            if let r = record?.typeRef, (isGPointer && typeRef.type.name == record?.name) || typeRef.isDirectPointer(to: r) {
                return true
            } else {
                return false
            }
        }

        /// return whether the type is a magical `gpointer` or related
        /// - Note: This returns `false` if the indirection level is non-zero (e.g. for a `gpointer *`)
        @inlinable
        public var isGPointer: Bool {
            guard typeRef.indirectionLevel == 0 else { return false }
            let type = typeRef.type
            let name = type.typeName
            return name == GIR.gpointer || name == GIR.gconstpointer
        }

        /// return whether the receiver is an instance of the given record (class) or any of its ancestors
        @inlinable
        public func isInstanceOfHierarchy(_ record: GIR.Record) -> Bool {
            if isInstanceOf(record) { return true }
            guard let parent = record.parentType else { return false }
            return isInstanceOfHierarchy(parent)
        }

        /// indicates whether the receiver is any known kind of pointer
        @inlinable
        public var isAnyKindOfPointer: Bool {
            guard typeRef.indirectionLevel == 0 else { return true }
            let type = typeRef.type
            let name = type.name
            return isGPointer || name.maybeCallback
        }

        /// indicates whether the receiver is an array of scalar values
        @inlinable
        public var isScalarArray: Bool { return isArray && !isAnyKindOfPointer }

        /// return the Swift camel case name, quoted if necessary
        @inlinable
        public var camelQuoted: String { name.camelCase.swiftQuoted }

        /// return a non-clashing argument name
        @inlinable
        public var nonClashingName: String {
            let sw = name.swift
            let nt = sw + (sw.isKnownType ? "_" : "")
            let type = typeRef.type
            let ctype = type.ctype
            let ct = ctype.innerCType.swiftType // swift name for C type
            let st = ctype.innerCType.swift     // corresponding Swift type
            let nc = nt == ct ? nt + "_" : nt
            let ns = nc == st ? nc + "_" : nc
            let na = ns == type.swiftName  ? ns + "_" : ns
            return na
        }

        //// return the known type of the argument (nil if not known)
        @inlinable
        public var knownType: GIR.Datatype? { return GIR.knownDataTypes[typeRef.type.name] }
        
        //// return the known class/record of the argument (nil if not known)
        @inlinable
        public var knownRecord: GIR.Record? {
            typeRef.knownIndirectionLevel == 1 ? GIR.knownRecords[typeRef.type.name] : nil
        }
        
        //// return the known bitfield the argument represents (nil if not known)
        @inlinable
        public var knownBitfield: GIR.Bitfield? { return GIR.knownBitfields[typeRef.type.name] }

        /// indicates whether the receiver is a known type
        @inlinable
        public var isKnownType: Bool { return knownType != nil }

        /// indicates whether the receiver is a known class or record
        @inlinable
        public var isKnownRecord: Bool { return knownRecord != nil }

        /// indicates whether the receiver is a known bit field
        @inlinable
        public var isKnownBitfield: Bool { return knownBitfield != nil }
        
        /// return the non-prefixed argument name
        @inlinable
        public var argumentName: String { return name.argumentSplit.arg.camelQuoted }
    }

    /// a type alias is just a type with an underlying C type
    public class Alias: CType {
        /// String representation for an `Alias`
        public override var kind: String { return "Alias" }
    }


    /// an entry for a constant
    public class Constant: CType {
        /// String representation of `Constant`s
        public override var kind: String { return "Constant" }
        /// raw value
        public let value: Int

        /// Designated initialiser
        /// - Parameters:
        ///   - name: The name of the `Constant` to initialise
        ///   - type: The type of the enum
        ///   - ctype: underlying C type
        ///   - value: the value of the constant
        ///   - comment: Documentation text for the constant
        ///   - introspectable: Set to `true` if introspectable
        ///   - deprecated: Documentation on deprecation status if non-`nil`
        public init(name: String, type: TypeReference, value: Int, comment: String, introspectable: Bool = false, deprecated: String? = nil) {
            self.value = value
            super.init(name: name, type: type, comment: comment, introspectable: introspectable, deprecated: deprecated)
        }

        /// Initialiser to construct a constant from XML
        /// - Parameters:
        ///   - node: `XMLElement` to construct this constant from
        ///   - index: Index within the siblings of the `node`
        ///   - nameAttr: Key for the attribute to extract the `name` property from
        public init(node: XMLElement, at index: Int, nameAttr: String = "name") {
            if let val = node.attribute(named: "value"), let v = Int(val) {
                value = v
            } else {
                value = index
            }
            super.init(node: node, at: index, nameAttr: nameAttr)
        }
    }


    /// an enumeration entry
    public class Enumeration: Datatype {
        /// String representation of `Enumeration`s
        public override var kind: String { return "Enumeration" }
        /// an enumeration value in C is a constant
        public typealias Member = Constant

        /// enumeration values
        public let members: [Member]

        /// Designated initialiser
        /// - Parameters:
        ///   - name: The name of the `Enumeration` to initialise
        ///   - type: C typedef name of the enum
        ///   - members: the cases for this enum
        ///   - comment: Documentation text for the enum
        ///   - introspectable: Set to `true` if introspectable
        ///   - deprecated: Documentation on deprecation status if non-`nil`
        public init(name: String, type: TypeReference, members: [Member], comment: String, introspectable: Bool = false, deprecated: String? = nil) {
            self.members = members
            super.init(name: name, type: type, comment: comment, introspectable: introspectable, deprecated: deprecated)
        }

        /// Initialiser to construct an enumeration from XML
        /// - Parameters:
        ///   - node: `XMLElement` to construct this enum from
        ///   - index: Index within the siblings of the `node`
        public init(node: XMLElement, at index: Int) {
            let mem = node.children.lazy.filter { $0.name == "member" }
            members = mem.enumerated().map { Member(node: $0.1, at: $0.0) }
            super.init(node: node, at: index)
        }

        /// Register this type as an enumeration type
        @inlinable
        override public func registerKnownType() {
            if !GIR.enums.contains(typeRef.type) {
                GIR.enums.insert(typeRef.type)
            }
        }
    }

    /// a bitfield is defined akin to an enumeration
    public class Bitfield: Enumeration {
        /// String representation of `Bitfield`s
        public override var kind: String { return "Bitfield" }

        /// Register this type as an enumeration type
        @inlinable
        override public func registerKnownType() {
            let type = typeRef.type
            let ctype = GIRType(name: type.typeName, typeName: type.typeName, ctype: type.ctype)

            if !GIR.bitfields.contains(ctype) {
                let c = BitfieldTypeConversion(source: ctype, target: type)
                type.conversions[ctype] = [c, c]
                GIR.bitfields.insert(ctype)
            }

            if !GIR.bitfields.contains(type) {
                let c = BitfieldTypeConversion(source: type, target: ctype)
                type.conversions[ctype] = [c, c]
                GIR.bitfields.insert(type)
            }
        }
    }


    /// a data type record to create a protocol/struct/class for
    public class Record: CType {
        /// String representation of `Record`s
        public override var kind: String { return "Record" }
        /// C language symbol prefix
        public let cprefix: String
        /// C type getter function
        public let typegetter: String
        /// Methods associated with this record
        public let methods: [Method]
        /// Functions associated with this record
        public let functions: [Function]
        /// Constructors for this record
        public let constructors: [Method]
        /// Properties of this record
        public let properties: [Property]
        /// Fieldss of this record
        public let fields: [Field]
        /// List of signals for this record
        public let signals: [Signal]
        /// Type struct (e.g. class definition), typically nil for records
        public var typeStruct: String?
        /// Name of the function that returns the GType for this record (`nil` if unspecified)
        public var parentType: Record? { return nil }
        /// Root class (`nil` for plain records)
        public var rootType: Record { return self }
        /// Names of implemented interfaces
        public var implements: [String]
        /// records contained within this record
        public var records: [Record] = []

        /// return all functions, methods, and constructors
        public var allMethods: [Method] {
            return constructors + methods + functions
        }

        /// return all functions, methods, and constructors inherited from ancestors
        public var inheritedMethods: [Method] {
            guard let parent = parentType else { return [] }
            return parent.allMethods + parent.inheritedMethods
        }

        /// return the typed pointer name
        @inlinable public var ptrName: String { cprefix + "_ptr" }

        /// Designated initialiser
        /// - Parameters:
        ///   - name: The name of the record to initialise
        ///   - type: C typedef name of the constant
        ///   - ctype: underlying C type
        ///   - cprefix: prefix used for C language free functions that implement methods for this record
        ///   - typegetter: C type getter function
        ///   - methods: Methods associated with this record
        ///   - functions: Functions associated with this record
        ///   - constructors: Constructors for this record
        ///   - properties: Properties of this record
        ///   - fields: Fields of this record
        ///   - signals: List of signals for this record
        ///   - interfaces: Interfaces implemented by this record
        ///   - comment: Documentation text for the constant
        ///   - introspectable: Set to `true` if introspectable
        ///   - deprecated: Documentation on deprecation status if non-`nil`
        public init(name: String, type: TypeReference, cprefix: String, typegetter: String, methods: [Method] = [], functions: [Function] = [], constructors: [Method] = [], properties: [Property] = [], fields: [Field] = [], signals: [Signal] = [], interfaces: [String] = [], comment: String = "", introspectable: Bool = false, deprecated: String? = nil) {
            self.cprefix = cprefix
            self.typegetter = typegetter
            self.methods = methods
            self.functions = functions
            self.constructors = constructors
            self.properties = properties
            self.fields = fields
            self.signals = signals
            self.implements = interfaces
            super.init(name: name, type: type, comment: comment, introspectable: introspectable, deprecated: deprecated)
        }

        /// Initialiser to construct a record type from XML
        /// - Parameters:
        ///   - node: `XMLElement` to construct this constant from
        ///   - index: Index within the siblings of the `node`
        public init(node: XMLElement, at index: Int) {
            cprefix = node.attribute(named: "symbol-prefix") ?? ""
            typegetter = node.attribute(named: "get-type") ?? ""
            typeStruct = node.attribute(named: "type-struct")
            let children = node.children.lazy
            let funcs = children.filter { $0.name == "function" }
            functions = funcs.enumerated().map { Function(node: $0.1, at: $0.0) }
            let meths = children.filter { $0.name == "method" }
            methods = meths.enumerated().map { Method(node: $0.1, at: $0.0) }
            let cons = children.filter { $0.name == "constructor" }
            constructors = cons.enumerated().map { Method(node: $0.1, at: $0.0) }
            let props = children.filter { $0.name == "property" }
            properties = props.enumerated().map { Property(node: $0.1, at: $0.0) }
            let fattrs = children.filter { $0.name == "field" }
            fields = fattrs.enumerated().map { Field(node: $0.1, at: $0.0) }
            let sigs = children.filter { $0.name == "signal" }
            signals = sigs.enumerated().map { Signal(node: $0.1, at: $0.0) }
            let interfaces = children.filter { $0.name == "implements" }
            implements = interfaces.enumerated().compactMap { $0.1.attribute(named: "name") }
            records = node.children.lazy.filter { $0.name ==  "record" }.enumerated().map {
                Record(node: $0.element, at: $0.offset)
            }
            super.init(node: node, at: index)
        }

        /// Register this type as a record type
        @inlinable
        override public func registerKnownType() {
            let type = typeRef.type
            let clsType = classType
            let proType = protocolType
            let refType = structType
            let protocolRef = self.protocolRef
            let clsRef = classRef
            if type.parent == nil { type.parent = protocolRef }
            if !GIR.recordTypes.contains(type) {
                GIR.recordTypes.insert(type)
            }
            let ref = structRef
            if GIR.protocols[type] == nil     { GIR.protocols[type]     = protocolRef }
            if GIR.protocols[clsType] == nil  { GIR.protocols[clsType]  = clsRef }
            if GIR.protocols[refType] == nil  { GIR.protocols[refType]  = protocolRef }
            if GIR.recordRefs[type] == nil    { GIR.recordRefs[type]    = ref }
            if GIR.recordRefs[clsType] == nil { GIR.recordRefs[clsType] = ref }
            if GIR.recordRefs[refType] == nil { GIR.recordRefs[refType] = ref }
            if GIR.recordRefs[proType] == nil { GIR.recordRefs[proType] = ref }
            if GIR.refRecords[proType] == nil { GIR.refRecords[proType] = typeRef }
            if GIR.refRecords[clsType] == nil { GIR.refRecords[clsType] = typeRef }
            if GIR.refRecords[refType] == nil { GIR.refRecords[refType] = typeRef }
            if GIR.refRecords[type] == nil    { GIR.refRecords[type]    = typeRef }
            let prefixedType = type.prefixed
            guard prefixedType !== type else { return }
            let prefixedCls = clsType.prefixed
            let prefixedRef = refType.prefixed
            let prefixedPro = proType.prefixed
            if GIR.protocols[prefixedType] == nil  { GIR.protocols[prefixedType]  = protocolRef }
            if GIR.protocols[prefixedCls] == nil   { GIR.protocols[prefixedCls]   = clsRef }
            if GIR.protocols[prefixedRef] == nil   { GIR.protocols[prefixedRef]   = protocolRef }
            if GIR.recordRefs[prefixedType] == nil { GIR.recordRefs[prefixedType] = ref }
            if GIR.recordRefs[prefixedCls] == nil  { GIR.recordRefs[prefixedCls]  = ref }
            if GIR.recordRefs[prefixedRef] == nil  { GIR.recordRefs[prefixedRef]  = ref }
            if GIR.recordRefs[prefixedPro] == nil  { GIR.recordRefs[prefixedPro]  = ref }
            if GIR.refRecords[prefixedPro] == nil  { GIR.refRecords[prefixedPro]  = typeRef }
            if GIR.refRecords[prefixedCls] == nil  { GIR.refRecords[prefixedCls]  = typeRef }
            if GIR.refRecords[prefixedRef] == nil  { GIR.refRecords[prefixedRef]  = typeRef }
            if GIR.refRecords[prefixedType] == nil { GIR.refRecords[prefixedType] = typeRef }
        }

        /// Name of the Protocol for this record
        @inlinable
        public var protocolName: String { typeRef.type.swiftName.protocolName }
        /// Name of the `Ref` struct for this record
        @inlinable
        public var structName: String { typeRef.type.swiftName + "Ref" }

        /// Type of the Class for this record
        @inlinable public var classType: GIRRecordType {
            let n = typeRef.type.swiftName.swift
            return GIRRecordType(name: n, typeName: n, ctype: typeRef.type.ctype)
        }

        /// Type of the Protocol for this record
        @inlinable public var protocolType: GIRType { GIRType(name: protocolName, typeName: protocolName, ctype: "") }

        /// Protocol reference for this record
        @inlinable public var protocolRef: TypeReference { TypeReference(type: protocolType) }

        /// Type of the `Ref` struct for this record
        @inlinable
        public var structType: GIRRecordType { GIRRecordType(name: structName, typeName: structName, ctype: "", superType: protocolRef) }

        /// Struct reference for this record
        @inlinable public var structRef: TypeReference { TypeReference(type: structType) }

        /// Class reference for this record
        @inlinable public var classRef: TypeReference { TypeReference(type: classType) }

        /// return the first method where the passed predicate closure returns `true`
        public func methodMatching(_ predictate: (Method) -> Bool) -> Method? {
            return allMethods.lazy.filter(predictate).first
        }

        /// return the first inherited method where the passed predicate closure returns `true`
        public func inheritedMethodMatching(_ predictate: (Method) -> Bool) -> Method? {
            return inheritedMethods.lazy.filter(predictate).first
        }

        /// return the first of my own or inherited methods where the passed predicate closure returns `true`
        public func anyMethodMatching(_ predictate: (Method) -> Bool) -> Method? {
            if let match = methodMatching(predictate) { return match }
            return inheritedMethodMatching(predictate)
        }

        /// return the `retain` (ref) method for the given record, if any
        public var ref: Method? { return anyMethodMatching { $0.isRef && $0.args.first!.isInstanceOfHierarchy(self) } }

        /// return the `release` (unref) method for the given record, if any
        public var unref: Method? { return anyMethodMatching { $0.isUnref && $0.args.first!.isInstanceOfHierarchy(self) } }

        /// return whether the record or one of its parents has a given property
        public func has(property name: String) -> Bool {
            guard properties.first(where: { $0.name == name }) == nil else { return true }
            guard let parent = parentType else { return false }
            return parent.has(property: name)
        }

        /// return only the properties that are not derived
        public var nonDerivedProperties: [Property] {
            guard let parent = parentType else { return properties }
            return properties.filter { !parent.has(property: $0.name) }
        }

        /// return all properties, including the ones derived from ancestors
        public var allProperties: [Property] {
            guard let parent = parentType else { return properties }
            let all = Set(properties).union(Set(parent.allProperties))
            return all.sorted()
        }

        /// return all signals, including the ones derived from ancestors
        public var allSignals: [Signal] {
            guard let parent = parentType else { return signals }
            let all = Set(signals).union(Set(parent.allSignals))
            return all.sorted()
        }
    }
    
    /// a union data type record
    public class Union: Record {
        /// String representation of `Union`s
        public override var kind: String { return "Union" }
    }

    /// a class data type record
    public class Class: Record {
        /// String representation of `Class`es
        public override var kind: String { return "Class" }
        /// parent class name
        public let parent: String

        /// return the parent type of the given class
        public override var parentType: Record? {
            guard !parent.isEmpty else { return nil }
            return GIR.knownDataTypes[parent] as? GIR.Record
        }

        /// return the top level ancestor type of the given class
        public override var rootType: Record {
            guard parent != "" else { return self }
            guard let p = GIR.knownDataTypes[parent] as? GIR.Record else { return self }
            return p.rootType
        }

        /// Initialiser to construct a class type from XML
        /// - Parameters:
        ///   - node: `XMLElement` to construct this constant from
        ///   - index: Index within the siblings of the `node`
        override init(node: XMLElement, at index: Int) {
            var parent = node.attribute(named: "parent") ?? ""
            if parent.isEmpty {
                parent = node.children.lazy.filter { $0.name ==  "prerequisite" }.first?.attribute(named: "name") ?? ""
            }
            self.parent = parent
            super.init(node: node, at: index)
        }
    }

    /// an inteface is similar to a class,
    /// but can be part of a more complex type graph
    public class Interface: Class {
        /// String representation of `Interface`es
        public override var kind: String { return "Interface" }
    }

    /// data type representing a function/method
    public class Method: Argument {     // superclass type is return type
        /// String representation of member `Method`s
        public override var kind: String { return "Method" }
        /// Original C function name
        public let cname: String
        /// Return type
        public let returns: Argument
        /// All associated arguments (parameters) in order
        public let args: [Argument]
        /// `true` if this method throws an error
        public let throwsError: Bool

        /// Designated initialiser
        /// - Parameters:
        ///   - name: The name of the method
        ///   - cname: C function name
        ///   - returns: return type
        ///   - args: Array of parameters
        ///   - comment: Documentation text for the method
        ///   - introspectable: Set to `true` if introspectable
        ///   - deprecated: Documentation on deprecation status if non-`nil`
        ///   - throwsAnError: Set to `true` if this method can throw an error
        public init(name: String, cname: String, returns: Argument, args: [Argument] = [], comment: String = "", introspectable: Bool = false, deprecated: String? = nil, throwsAnError: Bool = false) {
            self.cname = cname
            self.returns = returns
            self.args = args
            throwsError = throwsAnError
            super.init(name: name, type: returns.typeRef, instance: returns.instance, comment: comment, introspectable: introspectable, deprecated: deprecated)
        }

        /// Initialiser to construct a method type from XML
        /// - Parameters:
        ///   - node: `XMLElement` to construct this constant from
        ///   - index: Index within the siblings of the `node`
        public init(node: XMLElement, at index: Int) {
            cname = node.attribute(named: "identifier") ?? ""
            let thrAttr = node.attribute(named: "throws") ?? "0"
            throwsError = (Int(thrAttr) ?? 0) != 0
            let children = node.children.lazy
            if let ret = children.first(where: { $0.name == "return-value"}) {
                let arg = Argument(node: ret, at: -1)
                returns = arg
            } else {
                returns = Argument(name: "", type: .void, instance: false, comment: "")
            }
            if let params = children.first(where: { $0.name == "parameters"}) {
                let children = params.children.lazy
                args = GIR.args(children: children)
            } else {
                args = GIR.args(children: children)
            }
            super.init(node: node, at: index, varargs: args.lazy.filter({$0.varargs}).first != nil)
        }

        /// indicate whether this is an unref method
        public var isUnref: Bool {
            return args.count == 1 && name == "unref"
        }

        /// indicate whether this is a ref method
        public var isRef: Bool {
            return args.count == 1 && name == "ref"
        }

        /// indicate whether this is a getter method
        public var isGetter: Bool {
            return args.count == 1  && ( name.hasPrefix("get_") || name.hasPrefix("is_"))
        }

        /// indicate whether this is a setter method
        public var isSetter: Bool {
            return args.count == 2 && name.hasPrefix("set_")
        }

        /// indicate whether this is a setter method for the given getter
        public func isSetterFor(getter: String) -> Bool {
            guard args.count == 2 else { return false }
            let u = getter.utf8
            let s = u.index(after: u.startIndex)
            let e = u.endIndex
            let v = u[s..<e]
            let setter = "s" + String(Substring(v))
            return name == setter
        }

        /// indicate whether this is a getter method for the given setter
        public func isGetterFor(setter: String) -> Bool {
            guard args.count == 1 else { return false }
            let u = setter.utf8
            let s = u.index(after: u.startIndex)
            let e = u.endIndex
            let v = u[s..<e]
            let getter = "g" + String(Substring(v))
            return name == getter
        }
    }

    /// a function is the same as a method
    public class Function: Method {
        public override var kind: String { return "Function" }

        public override init(node: XMLElement, at index: Int) {
            super.init(node: node, at: index)
        }
    }

    /// a callback is the same as a function,
    /// except that the type definition is a `@convention(c)` callback definition
    public class Callback: Function {
        public override var kind: String { return "Callback" }
    }

    /// a signal is equivalent to a function
    public class Signal: Function {
        public override var kind: String { return "Signal" }
    }

    /// a property is a C type
    public class Property: CType {
        public override var kind: String { return "Property" }
    }

    /// a field is a Property
    public class Field: Property {
        public override var kind: String { return "Field" }

        public init(node: XMLElement, at index: Int) {
            super.init(fromChildrenOf: node, at: index)
        }
    }
    
    /// data type representing a function/method argument or return type
    public class Argument: CType {
        public override var kind: String { return "Argument" }
        public let instance: Bool           ///< is this an instance parameter or return type?
        public let _varargs: Bool           ///< is this a varargs (...) parameter?
        public let isNullable: Bool         ///< is this a nullable parameter or return type?
        public let allowNone: Bool          ///< is this a parameter that can be ommitted?
        public let isOptional: Bool         ///< is this an optional (out) parameter?
        public let callerAllocates: Bool    ///< is this a caller-allocated (out) parameter?
        public let ownershipTransfer: OwnershipTransfer ///< model of ownership transfer used
        public let direction: ParameterDirection        ///< whether this is an `in`, `out`, or `inout` parameter

        /// indicate whether the given parameter is varargs
        public var varargs: Bool {
            return _varargs || name.hasPrefix("...")
        }

        /// default constructor
        public init(name: String, type: TypeReference, instance: Bool, comment: String, introspectable: Bool = false, deprecated: String? = nil, varargs: Bool = false, isNullable: Bool = false, allowNone: Bool = false, isOptional: Bool = false, callerAllocates: Bool = false, ownershipTransfer: OwnershipTransfer = .none, direction: ParameterDirection = .in) {
            self.instance = instance
            _varargs = varargs
            self.isNullable = isNullable
            self.allowNone = allowNone
            self.isOptional = isOptional
            self.callerAllocates = callerAllocates
            self.ownershipTransfer = ownershipTransfer
            self.direction = direction
            super.init(name: name, type: type, comment: comment, introspectable: introspectable, deprecated: deprecated)
        }

        /// XML constructor
        public init(node: XMLElement, at index: Int, defaultDirection: ParameterDirection = .in) {
            instance = node.name.hasPrefix("instance")
            _varargs = node.children.lazy.first(where: { $0.name == "varargs"}) != nil
            let allowNone = node.attribute(named: "allow-none")
            if let allowNone = allowNone, !allowNone.isEmpty && allowNone != "0" && allowNone != "false" {
                self.allowNone = true
            } else {
                self.allowNone = false
            }
            if let nullable = node.attribute(named: "nullable") ?? allowNone, !nullable.isEmpty && nullable != "0" && nullable != "false" {
                isNullable = true
            } else {
                isNullable = false
            }
            if let optional = node.attribute(named: "optional") ?? allowNone, !optional.isEmpty && optional != "0" && optional != "false" {
                isOptional = true
            } else {
                isOptional = false
            }
            if let callerAlloc = node.attribute(named: "caller-allocates"), !callerAlloc.isEmpty && callerAlloc != "0" && callerAlloc != "false" {
                callerAllocates = true
            } else {
                callerAllocates = false
            }
            ownershipTransfer = node.attribute(named: "transfer-ownership").flatMap { OwnershipTransfer(rawValue: $0) } ?? .none
            direction = node.attribute(named: "direction").flatMap { ParameterDirection(rawValue: $0) } ?? defaultDirection
            super.init(fromChildrenOf: node, at: index)
        }

        /// XML constructor for functions/methods/callbacks
        public init(node: XMLElement, at index: Int, varargs: Bool, defaultDirection: ParameterDirection = .in) {
            instance = node.name.hasPrefix("instance")
            _varargs = varargs
            let allowNone = node.attribute(named: "allow-none")
            if let allowNone = allowNone, !allowNone.isEmpty && allowNone != "0" && allowNone != "false" {
                self.allowNone = true
            } else {
                self.allowNone = false
            }
            if let nullable = node.attribute(named: "nullable") ?? allowNone, nullable != "0" && nullable != "false" {
                isNullable = true
            } else {
                isNullable = false
            }
            if let optional = node.attribute(named: "optional") ?? allowNone, optional != "0" && optional != "false" {
                isOptional = true
            } else {
                isOptional = false
            }
            if let callerAlloc = node.attribute(named: "caller-allocates"), callerAlloc != "0" && callerAlloc != "false" {
                callerAllocates = true
            } else {
                callerAllocates = false
            }
            ownershipTransfer = node.attribute(named: "transfer-ownership").flatMap { OwnershipTransfer(rawValue: $0) } ?? .none
            direction = node.attribute(named: "direction").flatMap { ParameterDirection(rawValue: $0) } ?? defaultDirection
            super.init(node: node, at: index)
        }
    }
}
