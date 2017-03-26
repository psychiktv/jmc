//
//  LibraryManagerViewController.swift
//  jmc
//
//  Created by John Moody on 2/13/17.
//  Copyright © 2017 John Moody. All rights reserved.
//

import Cocoa
import DiskArbitration

class TrackNotFound: NSObject {
    var path: String?
    let track: Track
    var trackDescription: String
    init(path: String?, track: Track) {
        self.path = path
        self.track = track
        self.trackDescription = "\(track.artist?.name) - \(track.album?.name) - \(track.name)"
    }
}

class NewMediaURL: NSObject {
    let url: URL
    var toImport: Bool
    init(url: URL) {
        self.url = url
        self.toImport = true
    }
}

class LibraryManagerViewController: NSViewController, NSTableViewDelegate, NSTabViewDelegate {
    
    var fileManager = FileManager.default
    var databaseManager = DatabaseManager()
    var locationManager = (NSApplication.shared().delegate as! AppDelegate).locationManager!
    var library: Library?
    var missingTracks: [Track]?
    var newMediaURLs: [URL]?
    var delegate: AppDelegate?

    @IBOutlet weak var findNewMediaTabItem: NSTabViewItem!
    @IBOutlet weak var locationManagerTabItem: NSTabViewItem!
    @IBOutlet weak var sourceTableView: NSTableView!
    
    //data controllers
    @IBOutlet var libraryArrayController: NSArrayController!
    @IBOutlet var tracksNotFoundArrayController: NSArrayController!
    @IBOutlet var newTracksArrayController: NSArrayController!
    
    //source information elements
    @IBOutlet weak var sourceTitleLabel: NSTextField!
    @IBOutlet weak var sourceNameField: NSTextField!
    @IBOutlet weak var sourceLocationStatusImage: NSImageView!
    @IBOutlet weak var sourceLocationStatusTextField: NSTextField!
    @IBOutlet weak var sourceMonitorStatusImageView: NSImageView!
    @IBOutlet weak var sourceMonitorStatusTextField: NSTextField!
    @IBOutlet weak var sourceLocationField: NSTextField!
    
    @IBOutlet weak var automaticallyAddFilesCheck: NSButton!
    @IBOutlet weak var enableDirectoryMonitoringCheck: NSButton!
    @IBAction func removeSourceButtonPressed(_ sender: Any) {
        
    }
    
    @IBAction func enableMonitoringCheckAction(_ sender: Any) {
        if enableDirectoryMonitoringCheck.state == NSOnState {
            library?.watches_directories = true as NSNumber
        } else {
            library?.watches_directories = false as NSNumber
        }
        initializeForLibrary(library: library!)
        self.locationManager.reinitializeEventStream()
        
    }
    @IBAction func automaticallyAddCheckAction(_ sender: Any) {
        library?.monitors_directories_for_new = automaticallyAddFilesCheck.state == NSOnState ? true as NSNumber : false as NSNumber
    }
    @IBAction func sourceNameWasEdited(_ sender: Any) {
        if let textField = sender as? NSTextField, textField.stringValue != "" {
            library?.name = textField.stringValue
            initializeForLibrary(library: library!)
        }
    }
    
    func tabView(_ tabView: NSTabView, shouldSelect tabViewItem: NSTabViewItem?) -> Bool {
        if libraryIsAvailable(library: self.library!) {
            return true
        } else {
            if tabViewItem! == locationManagerTabItem || tabViewItem! == findNewMediaTabItem {
                return false
            } else {
                return true
            }
        }
    }
    @IBAction func changeSourceLocationButtonPressed(_ sender: Any) {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = false
        openPanel.runModal()
        if openPanel.urls.count > 0 {
            let newURL = openPanel.urls[0]
            changeLibraryLocation(library: self.library!, newLocation: newURL)
            initializeForLibrary(library: self.library!)
        }
    }
    
    func initializeForLibrary(library: Library) {
        print("init for \(library.name)")
        self.library = library
        sourceTitleLabel.stringValue = ("Information for \(library.name!):")
        sourceNameField.stringValue = library.name!
        let sourceLocationURL = URL(string: library.library_location!)!
        sourceLocationField.stringValue = sourceLocationURL.path
        var isDirectory = ObjCBool(Bool(0))
        let libraryWasAvailable = library.is_available
        let libraryIsNowAvailable = libraryIsAvailable(library: library)
        if libraryIsNowAvailable {
            sourceLocationStatusImage.image = NSImage(named: "NSStatusAvailable")
            sourceLocationStatusTextField.stringValue = "Source is located and available."
            enableDirectoryMonitoringCheck.isEnabled = true
            if let session = DASessionCreate(kCFAllocatorDefault), library.watches_directories == true {
                var volumeURL: AnyObject?
                do {
                    try (sourceLocationURL as NSURL).getResourceValue(&volumeURL, forKey: URLResourceKey.volumeURLKey)
                    if let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, volumeURL as! NSURL) {
                        let diskInformation = DADiskCopyDescription(disk) as! [String: AnyObject]
                        if diskInformation[kDADiskDescriptionMediaRemovableKey as String] != nil {
                            let removable = diskInformation[kDADiskDescriptionMediaRemovableKey as String] as! CFBoolean
                            if removable == kCFBooleanTrue {
                                sourceMonitorStatusImageView.image = NSImage(named: "NSStatusPartiallyAvailable")
                                sourceMonitorStatusTextField.stringValue = "Directory is on an external drive. Directory monitoring is active, but if another computer has modified the contents of this directory, you may need to re-verify the locations of media, or re-scan the directory if new media has been added."
                            }  else {
                                sourceMonitorStatusImageView.image = NSImage(named: "NSStatusAvailable")
                                sourceMonitorStatusTextField.stringValue = "Directory monitoring is active."
                            }
                        } else {
                            if diskInformation[kDADiskDescriptionVolumeNetworkKey as String] != nil {
                                let networkStatus = diskInformation[kDADiskDescriptionVolumeNetworkKey as String] as! CFBoolean
                                if networkStatus == kCFBooleanTrue {
                                    sourceMonitorStatusImageView.image = NSImage(named: "NSStatusPartiallyAvailable")
                                    sourceMonitorStatusTextField.stringValue = "Directory is remote. Directory monitoring is active, but if another computer has modified the contents of this directory, you may need to re-verify the locations of media, or re-scan the directory if new media has been added."
                                }
                            } else {
                                sourceMonitorStatusImageView.image = NSImage(named: "NSStatusPartiallyAvailable")
                                sourceMonitorStatusTextField.stringValue = "Directory watch status unknown!"
                            }
                        }
                        automaticallyAddFilesCheck.isEnabled = true
                        automaticallyAddFilesCheck.state = library.monitors_directories_for_new == true ? NSOnState : NSOffState
                    }
                } catch {
                    print(error)
                }
            } else {
                enableDirectoryMonitoringCheck.state = NSOffState
                sourceMonitorStatusTextField.stringValue = "Directory monitoring inactive."
                sourceMonitorStatusImageView.image = NSImage(named: "NSStatusUnavailable")
                automaticallyAddFilesCheck.isEnabled = false
            }
        } else {
            sourceLocationStatusImage.image = NSImage(named: "NSStatusUnavailable")
            sourceLocationStatusTextField.stringValue = "Source cannot be located."
            enableDirectoryMonitoringCheck.isEnabled = false
            sourceMonitorStatusTextField.stringValue = "Directory monitoring inactive."
            sourceMonitorStatusImageView.image = NSImage(named: "NSStatusUnavailable")
            automaticallyAddFilesCheck.isEnabled = false
        }
        if libraryIsNowAvailable != (libraryWasAvailable as? Bool) {
            delegate?.mainWindowController?.sourceListViewController?.reloadData()
        }
    }
    
    //location manager
    @IBOutlet weak var lostTracksTableView: NSTableView!
    @IBOutlet weak var trackLocationStatusText: NSTextField!
    @IBOutlet weak var verifyLocationsButton: NSButton!
    @IBOutlet weak var libraryLocationStatusImageView: NSImageView!
    
    
    @IBAction func verifyLocationsPressed(_ sender: Any) {
        let parent = self.view.window?.windowController as! LibraryManagerSourceSelector
        parent.verifyLocationsSheet = LocationVerifierSheetController(windowNibName: "LocationVerifierSheetController")
        parent.window?.beginSheet(parent.verifyLocationsSheet!.window!, completionHandler: verifyLocationsModalComplete)
        DispatchQueue.global(priority: DispatchQueue.GlobalQueuePriority.default).async {
            self.missingTracks = self.databaseManager.verifyTrackLocations(visualUpdateHandler: parent.verifyLocationsSheet, library: self.library!)
            DispatchQueue.main.async {
                self.verifyLocationsModalComplete(response: 1)
            }
        }
    }
    func verifyLocationsModalComplete(response: NSModalResponse) {
        guard response != NSModalResponseCancel else {return}
        if self.missingTracks!.count > 0 {
            let trackNotFoundArray = self.missingTracks!.map({(track: Track) -> TrackNotFound in
                if let location = track.location {
                    if let url = URL(string: location) {
                        return TrackNotFound(path: url.path, track: track)
                    } else {
                        return TrackNotFound(path: location, track: track)
                    }
                } else {
                    return TrackNotFound(path: nil, track: track)
                }
            })
            self.libraryLocationStatusImageView.image = NSImage(named: "NSStatusPartiallyAvailable")
            self.trackLocationStatusText.stringValue = "\(self.missingTracks!.count) tracks not found."
            tracksNotFoundArrayController.content = trackNotFoundArray
        } else {
            self.libraryLocationStatusImageView.image = NSImage(named: "NSStatusAvailable")
            self.trackLocationStatusText.stringValue = "All tracks located."
        }
    }
    
    @IBAction func locateTrackButtonPressed(_ sender: Any) {
        print("locate pressed")
        let row = lostTracksTableView.row(for: (sender as! NSButton).superview as! NSTableCellView)
        let trackContainer = (tracksNotFoundArrayController.arrangedObjects as! [TrackNotFound])[row]
        let track = trackContainer.track
        let fileDialog = NSOpenPanel()
        fileDialog.allowsMultipleSelection =  false
        fileDialog.canChooseDirectories = false
        fileDialog.allowedFileTypes = VALID_FILE_TYPES
        fileDialog.runModal()
        if fileDialog.urls.count > 0 {
            let url = fileDialog.urls[0]
            track.location = url.absoluteString
            tracksNotFoundArrayController.removeObject(trackContainer)
            databaseManager.fixInfoForTrack(track: track)
            missingTracks!.remove(at: missingTracks!.index(of: track)!)
            lostTracksTableView.reloadData()
        }
    }
    
    //dir scanner
    @IBOutlet weak var newMediaTableView: NSTableView!
    @IBOutlet weak var dirScanStatusTextField: NSTextField!
    
    @IBAction func scanSourceButtonPressed(_ sender: Any) {
        let parent = self.view.window?.windowController as! LibraryManagerSourceSelector
        parent.mediaScannerSheet = MediaScannerSheet(windowNibName: "MediaScannerSheet")
        parent.window?.beginSheet(parent.mediaScannerSheet!.window!, completionHandler: scanMediaModalComplete)
        DispatchQueue.global(qos: DispatchQoS.QoSClass.default).async {
            self.newMediaURLs = self.databaseManager.scanForNewMedia(visualUpdateHandler: parent.mediaScannerSheet, library: self.library!)
            DispatchQueue.main.async {
                self.scanMediaModalComplete(response: 1)
            }
        }
    }
    
    func scanMediaModalComplete(response: NSModalResponse) {
        if self.newMediaURLs!.count > 0{
            newTracksArrayController.content = self.newMediaURLs!.map({return NewMediaURL(url: $0)})
            
            dirScanStatusTextField.stringValue = "\(self.newMediaURLs!.count) new media files found."
            newMediaTableView.reloadData()
        } else {
            dirScanStatusTextField.stringValue = "No new media found."
        }
    }
    
    @IBAction func importSelectedPressed(_ sender: Any) {
        let mediaURLsToAdd = (newTracksArrayController.arrangedObjects as! [NewMediaURL]).filter({return $0.toImport == true}).map({return $0.url})
        let errors = databaseManager.addTracksFromURLs(mediaURLsToAdd, to: self.library!)
        for url in mediaURLsToAdd {
            newMediaURLs!.remove(at: newMediaURLs!.index(of: url)!)
        }
        newTracksArrayController.content = self.newMediaURLs!.map({return NewMediaURL(url: $0)})
        newMediaTableView.reloadData()
    }
    
    @IBAction func selectAllPressed(_ sender: Any) {
        for trackContainer in (newTracksArrayController.arrangedObjects as! [NewMediaURL]) {
            trackContainer.toImport = true
        }
        newMediaTableView.reloadData()
    }
    
    @IBAction func selectNonePressed(_ sender: Any) {
        for trackContainer in (newTracksArrayController.arrangedObjects as! [NewMediaURL]) {
            trackContainer.toImport = false
        }
        newMediaTableView.reloadData()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
}
