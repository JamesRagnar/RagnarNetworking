import Foundation

enum SocketIOPacket: Sendable, Equatable {
    case connect(namespace: String, payload: SocketIOArgument?)
    case disconnect(namespace: String)
    case event(
        namespace: String,
        acknowledgementID: Int?,
        name: String,
        arguments: [SocketIOArgument]
    )
    case acknowledgement(
        namespace: String,
        acknowledgementID: Int,
        arguments: [SocketIOArgument]
    )
    case connectError(namespace: String, payload: SocketIOArgument)
    case binaryEvent(
        namespace: String,
        acknowledgementID: Int?,
        attachmentCount: Int,
        name: String,
        arguments: [SocketIOArgument]
    )
    case binaryAcknowledgement(
        namespace: String,
        acknowledgementID: Int,
        attachmentCount: Int,
        arguments: [SocketIOArgument]
    )
}
