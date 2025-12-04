//in Watch App
//replace the code in the InterfaceController file with this code
//connect label and button to messageLabel and send funcs

import WatchKit
import Foundation
import WatchConnectivity

class InterfaceController: WKInterfaceController, WCSessionDelegate {
    var session: WCSession!
    @IBOutlet var messageLabel: WKInterfaceLabel!

    override func awakeWithContext(context: AnyObject?) {
        super.awakeWithContext(context)
    }

    override func willActivate() {
        //method called when view is about to be visible to user on the watch
        super.willActivate()
        if (WCSession.isSupported()) {
            self.session = WCSession.defaultSession()
            self.session.delegate = self
            self.session.activateSession()
        }
    }

    override func didDeactivate() {
        //method called when watch view is not visible anymore
        super.didDeactivate()
    }

    @IBAction func sendMessageToWatch() {
        if (WCSession.isSupported()) {
            session.sendMessage(["b":"goodbye"], replyHandler: nil, errorHandler:nil)
        }
    }

    func session(session: WCSession, didReceiveMessage message: [String:AnyObject]) {
        //receiving message from phone
        self.messageLabel.setText(message["a"]! as? String)
    }
}