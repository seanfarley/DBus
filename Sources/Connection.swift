//
//  Connection.swift
//  DBus
//
//  Created by Alsey Coleman Miller on 2/25/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import CDBus

/// Type representing a connection to a remote application and associated incoming/outgoing message queues.
///
/// Several methods use the following terms:
///
/// - **read** means to fill the incoming message queue by reading from the socket.
/// - **write** means to drain the outgoing queue by writing to the socket.
/// - **dispatch** means to drain the incoming queue by invoking application-provided message handlers.
///
/// The method `readWriteDispatch()` for example does all three of these things, offering a simple alternative to a main loop.
///
/// In an application with a main loop, the read/write/dispatch operations are usually separate.
public final class DBusConnection {
    
    // MARK: - Properties
    
    public let shared: Bool
    
    // MARK: - Internal Properties
    
    internal let internalPointer: COpaquePointer
    
    // MARK: - Initialization
    
    deinit {
        
        // Connections created with dbus_connection_open_private() or dbus_bus_get_private() are not kept track of 
        /// or referenced by libdbus. The creator of these connections is responsible for calling dbus_connection_close() 
        /// prior to releasing the last reference, if the connection is not already disconnected.
        if shared == false {
            
            self.close()
        }
        
        dbus_connection_unref(internalPointer)
    }
    
    /// Gets a connection to a remote address.
    ///
    /// - Parameter address: The address to connect to.
    /// - Parameter shared: Whether the connection will be shared by subsequent callers,
    /// or a new dedicated connection should be created.
    public init(address: String, shared: Bool = true) throws {
        
        self.shared = shared
        
        let error = DBusErrorInternal()
        
        if shared {
            
            self.internalPointer = dbus_connection_open(address, error.internalPointer)
            
        } else {
            
            self.internalPointer = dbus_connection_open_private(address, error.internalPointer)
        }
        
        // check for error
        guard self.internalPointer != nil
            else { throw error.toError()! }
    }
    
    /// Connects to a bus daemon and registers the client with it.
    ///
    /// - Parameter busType: Bus type.
    /// - Parameter shared: Whether the connection will be shared by subsequent callers,
    /// or a new dedicated connection should be created.
    public init(busType: DBusBusType, shared: Bool = true) throws {
        
        self.shared = shared
        
        let error = DBusErrorInternal()
        
        let internalBusType = CDBus.DBusBusType(rawValue: busType.rawValue)
        
        if shared {
            
            self.internalPointer = dbus_bus_get(internalBusType, error.internalPointer)
            
        } else {
            
            self.internalPointer = dbus_bus_get_private(internalBusType, error.internalPointer)
        }
        
        // check for error
        guard self.internalPointer != nil
            else { throw error.toError()! }
    }
    
    // MARK: - Class Methods
    
    /// This method sets a global flag for whether `dbus_connection_new()` will set `SIGPIPE` behavior to `SIG_IGN`.
    public static func setChangeSIGPIPE(change: Bool) {
        
        dbus_connection_set_change_sigpipe(dbus_bool_t(change))
    }
    
    // MARK: - Methods
    
    /// As long as the connection is open, this function will block until it can read or write, 
    /// then read or write, then return `true`.
    ///
    /// If the connection is closed, the function returns `false`.
    ///
    /// - Note: Even after disconnection, messages may remain in the incoming queue that need to be processed.
    public func readWrite(timeout: Int = Int(DBUS_TIMEOUT_USE_DEFAULT)) -> Bool {
        
        return dbus_connection_read_write(internalPointer, CInt(timeout)).boolValue
    }
    
    /// If there are messages to dispatch, this method will call `DBusConnection.dispatch()` once, and return.
    /// If there are no messages to dispatch, this function will block until it can read or write, then read or write, then return.
    ///
    /// The way to think of this function is that it either makes some sort of progress, or it blocks. 
    /// Note that, while it is blocked on I/O, it cannot be interrupted (even by other threads), 
    /// which makes this function unsuitable for applications that do more than just react to received messages.
    ///
    /// - Returns: The return value indicates whether the disconnect message has been processed, 
    /// NOT whether the connection is connected. 
    /// This is important because even after disconnecting, you want to process any messages you received prior to the disconnect.
    public func readWriteDispatch(timeout: Int = Int(DBUS_TIMEOUT_USE_DEFAULT)) -> Bool {
        
        return dbus_connection_read_write_dispatch(internalPointer, CInt(timeout)).boolValue
    }
    
    /// Processes any incoming data.
    ///
    /// If there's incoming raw data that has not yet been parsed, it is parsed,
    /// which may or may not result in adding messages to the incoming queue.
    public func dispatch() -> DBusDispatchStatus {
        
        let rawValue = dbus_connection_dispatch(internalPointer).rawValue
        
        return DBusDispatchStatus(rawValue: rawValue)!
    }
    
    /// Closes a private connection, so no further data can be sent or received.
    ///
    //// This disconnects the transport (such as a socket) underlying the connection.
    public func close() {
        
        dbus_connection_close(internalPointer)
    }
    
    /// Tests whether a certain type can be send via the connection.
    public func canSend(type: DBusType) -> Bool {
        
        return dbus_connection_can_send_type(internalPointer, type.integerValue).boolValue
    }
    
    /// Adds a message to the outgoing message queue. 
    ///
    /// Does not block to write the message to the network; that happens asynchronously. 
    /// To force the message to be written, call `flush()`.
    ///
    /// - Parameter message: The message to write.
    ///
    /// - Parameter serial: Return location for message serial, or `nil` if you don't care.
    public func send(message: DBusMessage, serial: dbus_uint32_t? = nil) {
        
        let serialPointer: UnsafeMutablePointer<dbus_uint32_t>
        
        if let serial = serial {
            
            serialPointer = UnsafeMutablePointer<dbus_uint32_t>.alloc(1)
            
            serialPointer.memory = serial
            
            defer { serialPointer.dealloc(1) }
            
        } else {
            
            // nil pointer
            serialPointer = UnsafeMutablePointer<dbus_uint32_t>()
        }
        
        guard dbus_connection_send(internalPointer, message.internalPointer, serialPointer)
            else { fatalError("Out of memory! Could not add message to queue. (\(message))") }
    }
    
    /// Queues a message to send, as with `DBusConnection.send()`, 
    /// but also returns reply to the message.
    public func sendWithReply(message: DBusMessage, timeout: Int = Int(DBUS_TIMEOUT_USE_DEFAULT)) -> DBusPendingCall? {
        
        let pendingCallDoublePointer = UnsafeMutablePointer<COpaquePointer>.alloc(1)
        
        // free double pointer
        defer { pendingCallDoublePointer.dealloc(1) }
        
        guard dbus_connection_send_with_reply(internalPointer, message.internalPointer, pendingCallDoublePointer, CInt(timeout))
            else { fatalError("Out of memory! Could not add message to queue. (\(message))") }
        
        // if the connection is disconnected or you try to send Unix file descriptors on a connection that does not support them,
        // the DBusPendingCall will be set to NULL
        guard pendingCallDoublePointer != nil else { return nil }
        
        let pendingCallInternalPointer = pendingCallDoublePointer.memory
        
        return DBusPendingCall(pendingCallInternalPointer)
    }
    
    /// Blocks until the outgoing message queue is empty.
    public func flush() {
        
        dbus_connection_flush(internalPointer)
    }
    
    /// Returns the first-received message from the incoming message queue, removing it from the queue.
    ///
    /// If the queue is empty, returns `nil`.
    public func popMessage() -> DBusMessage? {
        
        let messageInternalPointer = dbus_connection_pop_message(internalPointer)
        
        guard messageInternalPointer != nil else { return nil }
        
        let message = DBusMessage(messageInternalPointer)
        
        return message
    }
    
    // MARK: - Dynamic Properties
    
    public var firstMessage: DBusMessage? {
        
        let messageInternalPointer = dbus_connection_borrow_message(internalPointer)
        
        guard messageInternalPointer != nil else { return nil }
        
        /// No one can get at the message while its borrowed, so return it as quickly as possible 
        /// and don't keep a reference to it after returning it. If you need to keep the message, make a copy of it.
        let borrowedMessage = DBusMessage(messageInternalPointer)
        
        let message = borrowedMessage.copy
        
        return message
    }
    
    /// Whether the connection is currently open.
    public var connected: Bool {
        
        return dbus_connection_get_is_connected(internalPointer).boolValue
    }
    
    /// Whether the connection was authenticated.
    public var authenticated: Bool {
        
        return dbus_connection_get_is_authenticated(internalPointer).boolValue
    }
    
    /// Whether the connection is not authenticated as a specific user.
    public var anonymous: Bool {
        
        return dbus_connection_get_is_anonymous(internalPointer).boolValue
    }
    
    /// Checks whether there are messages in the outgoing message queue.
    ///
    /// Use `DBusConnection.flush()` to block until all outgoing messages have been written to the underlying transport
    /// (such as a socket).
    public var hasMessages: Bool {
        
        return dbus_connection_has_messages_to_send(internalPointer).boolValue
    }
    
    /// Gets the ID of the server address we are authenticated to, if this connection is on the client side, 
    /// or `nil` if the connection is on the server side.
    public var serverIdentifier: String? {
        
        let cString = dbus_connection_get_server_id(internalPointer)
        
        guard cString != nil else { return nil }
        
        let stringValue = String.fromCString(cString)!
        
        return stringValue
    }
    
    /// The approximate size in bytes of all messages in the outgoing message queue.
    ///
    /// The size is approximate in that you shouldn't use it to decide how many bytes to read off the network 
    /// or anything of that nature, as optimizations may choose to tell small white lies to avoid performance overhead.
    public var outgoingSize: Int {
        
        return dbus_connection_get_outgoing_size(internalPointer)
    }
    
    /// The approximate number of file descriptors of all messages in the outgoing message queue.
    public var outgoingFileDescriptors: Int {
        
        return dbus_connection_get_outgoing_unix_fds(internalPointer)
    }
    
    /// Specifies the maximum size message this connection is allowed to receive.
    ///
    /// Larger messages will result in disconnecting the connection.
    public var maximumSize: Int {
        
        get { return dbus_connection_get_max_message_size(internalPointer) }
        
        set { dbus_connection_set_max_message_size(internalPointer, newValue) }
    }
    
    /// Specifies the maximum number of file descriptors a message on this connection is allowed to receive.
    ///
    /// Messages with more file descriptors will result in disconnecting the connection.
    public var maximumFileDescriptors: Int {
        
        get { return dbus_connection_get_max_message_unix_fds(internalPointer) }
        
        set { dbus_connection_set_max_message_unix_fds(internalPointer, newValue) }
    }
    
    /// Sets the maximum total number of bytes that can be used for all messages received on this connection.
    ///
    /// Messages count toward the maximum until they are finalized. 
    /// When the maximum is reached, the connection will not read more data until some messages are finalized.
    ///
    /// The semantics of the maximum are: if outstanding messages are already above the maximum, 
    /// additional messages will not be read.
    /// The semantics are not: if the next message would cause us to exceed the maximum, we don't read it. 
    /// The reason is that we don't know the size of a message until after we read it.
    ///
    /// Thus, the max live messages size can actually be exceeded by up to the maximum size of a single message.
    public var maximumRecievedSize: Int {
        
        get { return dbus_connection_get_max_received_size(internalPointer) }
        
        set { dbus_connection_set_max_received_size(internalPointer, newValue) }
    }
    
    /// Sets the maximum total number of unix fds that can be used for all messages received on this connection.
    ///
    /// Messages count toward the maximum until they are finalized. 
    /// When the maximum is reached, the connection will not read more data until some messages are finalized.
    ///
    /// The semantics are analogous to those of `maximumRecievedSize`.
    public var maximumRecievedFileDescriptors: Int {
        
        get { return dbus_connection_get_max_received_unix_fds(internalPointer) }
        
        set { dbus_connection_set_max_received_unix_fds(internalPointer, newValue) }
    }
    
}


