import React
import Photos
import ffmpegkit

@objc(VideoTrim)
class VideoTrim: RCTEventEmitter {
    private let FILE_PREFIX = "trimmedVideo"
    private var hasListeners = false
    private var isShowing = false
    
    private var saveToPhoto = true
    private var removeAfterSavedToPhoto = false
    private var trimmingText = "Trimming video..."
    
    @objc
    static override func requiresMainQueueSetup() -> Bool {
        return true
    }
    
    override func supportedEvents() -> [String]! {
        return ["VideoTrim"]
    }
    
    override func startObserving() {
        hasListeners = true
    }
    
    override func stopObserving() {
        hasListeners = false
    }
    
    @objc(isValidVideo:withResolver:withRejecter:)
    func isValidVideo(uri: String, resolve: @escaping RCTPromiseResolveBlock,reject: @escaping RCTPromiseRejectBlock) -> Void {
        if let destPath = copyFileToDocumentDir(uri: uri) {
            resolve(UIVideoEditorController.canEditVideo(atPath: destPath.path))
            let _ = deleteFile(url: destPath) // remove the file we just copied to document directory
        } else {
            resolve(false)
        }
    }
    
    @objc(showEditor:withConfig:)
    func showEditor(uri: String, config: NSDictionary){
        if isShowing {
            return
        }
  
        saveToPhoto = config["saveToPhoto"] as? Bool ?? true
        removeAfterSavedToPhoto = config["removeAfterSavedToPhoto"] as? Bool ?? false
        
        let enableCancelDialog = config["enableCancelDialog"] as? Bool ?? true
        let cancelDialogTitle = config["cancelDialogTitle"] as? String ?? "Warning!"
        let cancelDialogMessage = config["cancelDialogMessage"] as? String ?? "Are you sure want to cancel?"
        let cancelDialogCancelText = config["cancelDialogCancelText"] as? String ?? "Close"
        let cancelDialogConfirmText = config["cancelDialogConfirmText"] as? String ?? "Proceed"

        let enableSaveDialog = config["enableSaveDialog"] as? Bool ?? true
        let saveDialogTitle = config["saveDialogTitle"] as? String ?? "Confirmation!"
        let saveDialogMessage = config["saveDialogMessage"] as? String ?? "Are you sure want to save?"
        let saveDialogCancelText = config["saveDialogCancelText"] as? String ?? "Close"
        let saveDialogConfirmText = config["saveDialogConfirmText"] as? String ?? "Proceed"
        trimmingText = config["trimmingText"] as? String ?? "Trimming video..."
        let fullScreenModalIOS = config["fullScreenModalIOS"] as? Bool ?? false
        
        if let destPath = copyFileToDocumentDir(uri: uri) {
            if UIVideoEditorController.canEditVideo(atPath: destPath.path) {
                DispatchQueue.main.async {
                    if #available(iOS 13.0, *) {
                        let vc = VideoTrimmerViewController()
                        vc.asset = AVURLAsset(url: destPath, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
                        
                        if let maxDuration = config["maxDuration"] as? Int {
                            vc.maximumDuration = maxDuration
                        }
                        
                        if let minDuration = config["minDuration"] as? Int {
                            vc.minimumDuration = minDuration
                        }
                        
                        if let cancelBtnText = config["cancelButtonText"] as? String, !cancelBtnText.isEmpty {
                            vc.cancelBtnText = cancelBtnText
                        }
                        
                        if let saveButtonText = config["saveButtonText"] as? String, !saveButtonText.isEmpty {
                            vc.saveButtonText = saveButtonText
                        }
                        
                        vc.cancelBtnClicked = {
                            if !enableCancelDialog {
                                let _ = self.deleteFile(url: destPath) // remove the file we just copied to document directory
                                self.emitEventToJS("onCancelTrimming", eventData: nil)
                                
                                vc.dismiss(animated: true, completion: {
                                    self.emitEventToJS("onHide", eventData: nil)
                                    self.isShowing = false
                                })
                                return
                            }
                            
                            // Create Alert
                            let dialogMessage = UIAlertController(title: cancelDialogTitle, message: cancelDialogMessage, preferredStyle: .alert)

                            // Create OK button with action handler
                            let ok = UIAlertAction(title: cancelDialogConfirmText, style: .destructive, handler: { (action) -> Void in
                                let _ = self.deleteFile(url: destPath) // remove the file we just copied to document directory
                                self.emitEventToJS("onCancelTrimming", eventData: nil)
                                
                                vc.dismiss(animated: true, completion: {
                                    self.emitEventToJS("onHide", eventData: nil)
                                    self.isShowing = false
                                })
                            })

                            // Create Cancel button with action handlder
                            let cancel = UIAlertAction(title: cancelDialogCancelText, style: .cancel)

                            //Add OK and Cancel button to an Alert object
                            dialogMessage.addAction(ok)
                            dialogMessage.addAction(cancel)

                            // Present alert message to user
                            if let root = RCTPresentedViewController() {
                                root.present(dialogMessage, animated: true, completion: nil)
                            }
                        }
                        
                        vc.saveBtnClicked = {(selectedRange: CMTimeRange) in
                            if !enableSaveDialog {
                                self.trim(viewController: vc,inputFile: destPath, videoDuration: vc.asset.duration.seconds, startTime: selectedRange.start.seconds, endTime: selectedRange.end.seconds)
                                return
                            }
                            
                            // Create Alert
                            let dialogMessage = UIAlertController(title: saveDialogTitle, message: saveDialogMessage, preferredStyle: .alert)

                            // Create OK button with action handler
                            let ok = UIAlertAction(title: saveDialogConfirmText, style: .default, handler: { (action) -> Void in
                                self.trim(viewController: vc,inputFile: destPath, videoDuration: vc.asset.duration.seconds, startTime: selectedRange.start.seconds, endTime: selectedRange.end.seconds)
                            })

                            // Create Cancel button with action handlder
                            let cancel = UIAlertAction(title: saveDialogCancelText, style: .cancel)

                            //Add OK and Cancel button to an Alert object
                            dialogMessage.addAction(ok)
                            dialogMessage.addAction(cancel)

                            // Present alert message to user
                            if let root = RCTPresentedViewController() {
                                root.present(dialogMessage, animated: true, completion: nil)
                            }
                        }
                        
                        vc.isModalInPresentation = true // prevent modal closed by swipe down
                        
                        if fullScreenModalIOS {
                            vc.modalPresentationStyle = .fullScreen
                        }
                        
                        if let root = RCTPresentedViewController() {
                            root.present(vc, animated: true, completion: {
                                self.emitEventToJS("onShow", eventData: nil)
                                self.isShowing = true
                            })
                        }
                    }
                }
            } else {
                let eventPayload: [String: Any] = ["message": "File is not a valid video"]
                self.emitEventToJS("onError", eventData: eventPayload)
            }
        } else {
            let eventPayload: [String: Any] = ["message": "File is invalid"]
            self.emitEventToJS("onError", eventData: eventPayload)
        }
    }
    
    private func copyFileToDocumentDir(uri: String) -> URL? {
        if let videoURL = URL(string: uri) {
            // Save the video to the document directory
            let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            // Extract the file extension from the videoURL
            let fileExtension = videoURL.pathExtension
            
            // Define the filename with the correct file extension
            let timestamp = Int(Date().timeIntervalSince1970)
            let destinationURL = documentsDirectory.appendingPathComponent("\(FILE_PREFIX)_original_\(timestamp).\(fileExtension)")
            
            do {
                try FileManager.default.copyItem(at: videoURL, to: destinationURL)
            } catch {
                print("Error while copying file to document directory \(error)")
                return nil
            }
            
            return destinationURL
        } else {
            return nil
        }
    }
    
    private func emitEventToJS(_ eventName: String, eventData: [String: Any]?) {
        if hasListeners {
            var modifiedEventData = eventData ?? [:] // If eventData is nil, create an empty dictionary
            modifiedEventData["name"] = eventName
            sendEvent(withName: "VideoTrim", body: modifiedEventData)
        }
    }
    
    @objc(listFiles:withRejecter:)
    func listFiles(resolve: @escaping RCTPromiseResolveBlock,reject: @escaping RCTPromiseRejectBlock) -> Void {
        let files = listFiles()
        resolve(files.map{ $0.absoluteString })
    }
    
    @objc(cleanFiles:withRejecter:)
    func cleanFiles(resolve: @escaping RCTPromiseResolveBlock,reject: @escaping RCTPromiseRejectBlock) -> Void {
        let files = listFiles()
        var successCount = 0
        for file in files {
            let state = deleteFile(url: file)
            
            if state == 0 {
                successCount += 1
            }
        }
        
        resolve(successCount)
    }
    
    @objc(deleteFile:withResolver:withRejecter:)
    func deleteFile(uri: String, resolve: @escaping RCTPromiseResolveBlock,reject: @escaping RCTPromiseRejectBlock) -> Void {
        let state = deleteFile(url: URL(string: uri)!)
        resolve(state == 0)
    }
    
    private func listFiles() -> [URL] {
        var files: [URL] = []
        
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        
        do {
            let directoryContents = try FileManager.default.contentsOfDirectory(at: documentsDirectory, includingPropertiesForKeys: nil)
            
            for fileURL in directoryContents {
                if fileURL.lastPathComponent.starts(with: FILE_PREFIX) {
                    files.append(fileURL)
                }
            }
        } catch {
            print("[listFiles] Error when retrieving files: \(error)")
        }
        
        return files
    }
    
    private func deleteFile(url: URL) -> Int {
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
                
                return 0
            }
            
            return 1
        } catch {
            print("[deleteFile] Error deleting files: \(error)")
            
            return 2
        }
    }
    
    @available(iOS 13.0, *)
    private func trim(viewController: VideoTrimmerViewController, inputFile: URL, videoDuration: Double, startTime: Double, endTime: Double) {
        let timestamp = Int(Date().timeIntervalSince1970)
        let outputName = "\(FILE_PREFIX)_\(timestamp).mp4" // use mp4 to prevent any issue with ffmpeg about file extension
        let outputFile = "\(inputFile.deletingLastPathComponent().absoluteURL)\(outputName)"
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZ"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let dateTime = formatter.string(from: Date())
        
        self.emitEventToJS("onStartTrimming", eventData: nil)
        
        // Create Alert
        let dialogMessage = UIAlertController(title: trimmingText, message: nil, preferredStyle: .alert)

        // Present alert message to user
        let progressView = UIProgressView(frame: .zero)
        progressView.tintColor = .systemBlue
        if let root = RCTPresentedViewController() {
            root.present(dialogMessage, animated: true, completion: {
                dialogMessage.view.addSubview(progressView)
                
                progressView.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    progressView.leadingAnchor.constraint(equalTo: dialogMessage.view.leadingAnchor, constant: 8),
                    progressView.trailingAnchor.constraint(equalTo: dialogMessage.view.trailingAnchor, constant: -8),
                    progressView.bottomAnchor.constraint(equalTo: dialogMessage.view.bottomAnchor, constant: -8)
                ])
            })
        }
        
        let cmds = [
            "-ss",
            "\(startTime * 1000)ms",
            "-to",
            "\(endTime * 1000)ms",
            "-i",
            "\(inputFile)",
            "-c",
            "copy",
            "-metadata",
            "creation_time=\(dateTime)",
            outputFile
        ]
        
        FFmpegKit.execute(withArgumentsAsync: cmds, withCompleteCallback: { session in
            let _ = self.deleteFile(url: inputFile) // remove the file we just copied to document directory
            
            let state = session?.getState()
            let returnCode = session?.getReturnCode()
            
            if ReturnCode.isSuccess(returnCode) {
                let eventPayload: [String: Any] = ["outputPath": outputFile, "startTime": startTime, "endTime": endTime, "duration": videoDuration]
                self.emitEventToJS("onFinishTrimming", eventData: eventPayload)
                
                if (self.saveToPhoto) {
                    PHPhotoLibrary.requestAuthorization { status in
                        guard status == .authorized else {
                            let eventPayload: [String: Any] = ["message": "Permission to access Photo Library is not granted"]
                            self.emitEventToJS("onError", eventData: eventPayload)
                            return
                        }
                        
                        PHPhotoLibrary.shared().performChanges({
                            let request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: URL(string: outputFile)!)
                            request?.creationDate = Date()
                        }) { success, error in
                            if success {
                                print("Edited video saved to Photo Library successfully.")
                                
                                if self.removeAfterSavedToPhoto {
                                    let _ = self.deleteFile(url: URL(string: outputFile)!)
                                }
                            } else {
                                let eventPayload: [String: Any] = ["message": "Failed to save edited video to Photo Library: \(error?.localizedDescription ?? "Unknown error")"]
                                self.emitEventToJS("onError", eventData: eventPayload)
                            }
                        }
                    }
                }
            } else {
                // CANCEL + FAILURE
                let eventPayload: [String: Any] = ["message": "Command failed with state \(String(describing: FFmpegKitConfig.sessionState(toString: state ?? .failed))) and rc \(String(describing: returnCode)).\(String(describing: session?.getFailStackTrace()))"]
                self.emitEventToJS("onError", eventData: eventPayload)
            }
            
            // some how in case we trim a very short video the view controller is still visible after first .dismiss call
            // even the file is successfully saved
            // that's why we need a small delay here to ensure vc will be dismissed
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                dialogMessage.dismiss(animated: false)
                viewController.dismiss(animated: true, completion: {
                    self.emitEventToJS("onHide", eventData: nil)
                    self.isShowing = false
                })
            }
        }, withLogCallback: { log in
            guard let log = log else { return }
            
            print("FFmpeg process started with log " + (log.getMessage()));
            
            let eventPayload: [String: Any] = [
                "level": log.getLevel(),
                "message": log.getMessage() ?? "",
                "sessionId": log.getSessionId(),
            ]
            self.emitEventToJS("onLog", eventData: eventPayload)
            
        }, withStatisticsCallback: { statistics in
            guard let statistics = statistics else { return }

            let timeInMilliseconds = statistics.getTime()
            if timeInMilliseconds > 0 {
                let completePercentage = timeInMilliseconds / (videoDuration * 1000); // from 0 -> 1
                DispatchQueue.main.async {
                    progressView.setProgress(Float(completePercentage), animated: true)
                }
            }
            
            let eventPayload: [String: Any] = [
                "sessionId": statistics.getSessionId(),
                "videoFrameNumber": statistics.getVideoFrameNumber(),
                "videoFps": statistics.getVideoFps(),
                "videoQuality": statistics.getVideoQuality(),
                "size": statistics.getSize(),
                "time": statistics.getTime(),
                "bitrate": statistics.getBitrate(),
                "speed": statistics.getSpeed()
            ]
            self.emitEventToJS("onStatistics", eventData: eventPayload)
        })
    }
}
