//
//  QiscusWorkerManager.swift
//  QiscusCore
//
//  Created by Qiscus on 09/10/18.
//

import Foundation

public class QiscusWorkerManager {
    var qiscusCore : QiscusCore? = nil
    var isBackground : Bool = false
    func resume() {
        // MARK : Improve realtime state acurate disconnected
        if self.qiscusCore?.isLogined ?? false {
            self.sync()
            self.pending()
            DispatchQueue.main.sync {
                let state = UIApplication.shared.applicationState
                
                DispatchQueue.global(qos: .background).sync {
                    if state == .active {
                        // foreground
                        if self.qiscusCore?.realtime.state == .connected {
                            self.qiscusCore?.shared.publishOnlinePresence(isOnline: true)
                            isBackground = false
                        }
                    }else{
                        if isBackground == false {
                            isBackground = true
                            if self.qiscusCore?.realtime.state == .connected {
                                self.qiscusCore?.shared.publishOnlinePresence(isOnline: false)
                            }
                        }
                    }
                }
            }
        }
    }
    
    func resumeSyncEvent() {
           // MARK : Improve realtime state acurate disconnected
        if self.qiscusCore?.isLogined ?? false {
               self.syncAuto()
           }
       }
    
    private func syncEvent() {
        //sync event
        var id = self.qiscusCore?.config.syncEventId
        if id!.isEmpty{
            id = self.qiscusCore?.config.user?.lastSyncEventId ?? "0"
        }
        self.qiscusCore?.network.synchronizeEvent(lastEventId: id ?? "0", onSuccess: { (events) in
            if !events.isEmpty{
                self.qiscusCore?.config.syncEventId = events.first!.id
            }
            
            events.forEach({ (event) in
                DispatchQueue.global(qos: .background).sync {
                    if event.id == id { return }
                    
                    switch event.actionTopic {
                    case .deletedMessage :
                        let ids = event.getDeletedMessageUniqId()
                        ids.forEach({ (id) in
                            if let comment = self.qiscusCore?.database.message.find(uniqueId: id) {
                                _ = self.qiscusCore?.database.message.delete(comment)
                            }
                        })
                        self.qiscusCore?.config.syncEventId = event.id
                    case .clearRoom:
                        let ids = event.getClearRoomUniqId()
                        ids.forEach({ (id) in
                            if let room = self.qiscusCore?.database.room.find(uniqID: id) {
                                _ = self.qiscusCore?.database.message.clear(inRoom: room.id, timestamp: event.timestamp)
                            }
                        })
                        self.qiscusCore?.config.syncEventId = event.id
                        
                    case .noActionTopic:
                        break
                        
                    case .sent:
                        break
                        
                    case .delivered:
                        event.updatetStatusMessage()
                    case .read:
                        event.updatetStatusMessage()
                    }
                    
                }
               
            })
        }) { (error) in
            self.qiscusCore?.qiscusLogger.errorPrint("sync event error, \(error.message)")
        }
    }
    
   private func sync() {
        DispatchQueue.global(qos: .background).sync {
            if self.qiscusCore?.config.isConnectedMqtt == false {
                var id = self.qiscusCore?.config.syncId
                let latestComment = self.qiscusCore?.config.lastCommentId
                
                if latestComment != "" && id != "" {
                    if id == latestComment {
                        //id same
                    }else{
                        id = latestComment
                    }
                }
                
                self.qiscusCore?.synchronize(lastMessageId: id!, onSuccess: { (comments) in
                    self.syncEvent()
                    if let c = comments.first {
                        self.qiscusCore?.config.syncId = c.id
                    }
                }, onError: { (error) in
                    self.qiscusCore?.qiscusLogger.errorPrint("sync error, \(error.message)")
                })
            }
        }
        
    }
    
    //default is 30s
    private func syncAuto() {
        DispatchQueue.global(qos: .background).sync {
            if self.qiscusCore?.config.isConnectedMqtt == true {
                var id = self.qiscusCore?.config.syncId
                let latestComment = self.qiscusCore?.config.lastCommentId
                
                if latestComment != "" && id != "" {
                    if id == latestComment {
                        //id same
                    }else{
                        id = latestComment
                    }
                }

                self.qiscusCore?.synchronize(lastMessageId: id!, onSuccess: { (comments) in
                    self.syncEvent()
                    if let c = comments.first {
                        self.qiscusCore?.config.syncId = c.id
                    }
                }, onError: { (error) in
                    self.qiscusCore?.qiscusLogger.errorPrint("sync auto error, \(error.message)")
                })
            }
        }
    }
    
    private func pending() {
        guard let comments = self.qiscusCore?.database.message.find(status: .pending) else { return }
        comments.reversed().forEach { (c) in
            // validation comment prevent id
            if c.uniqueId.isEmpty { self.qiscusCore?.database.message.evaluate(); return }
            self.qiscusCore?.shared.sendMessage(message: c, onSuccess: { (response) in
                self.qiscusCore?.qiscusLogger.debugPrint("success send pending message \(response.uniqueId)")
            }, onError: { (error) in
                self.qiscusCore?.qiscusLogger.errorPrint("failed send pending message \(c.uniqueId)")
            })
        }
    }
}