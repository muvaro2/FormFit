//in Phone App
//replace the code in the ViewController file with this code
//connect label and button to messageLabel and send funcs

import UIKit
import WatchConnectivity

class ViewController: UIViewController, WCSessionDelegate {
    var session: WCSession!
    @IBOutlet var messageLabel: UILabel!
    override func viewDidLoad() {
        super.viewDidLoad()
        //additional setup if needed here
        if (WCSession.isSupported()) {
            self.session = WCSession.defaultSession()
            self.session.delegate = self
            self.session.activateSession()
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        //dispose of resources that can be recreated
    }

    @IBAction func sendMessageToWatch(sender: AnyObject) {
        //send message to watch
        session.sendMessage(["a":"hello"], replyHandler: nil, errorHandler:nil)
    }

    func session(session: WCSession, didReceiveMessage message: [String:AnyObject]) {
        //receive message from watch
        self.messageLabel.text = message["b"]! as? String
    }
}