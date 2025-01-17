/*
Licensed Materials - Property of IBM
© Copyright IBM Corporation 2014, 2015. All Rights Reserved.

*/


import UIKit
import CoreData

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    var window: UIWindow?
    var viewController:MILWebViewController?;
    var challengeHandler : ChallengeHandler!
    var username : String!
    var password : String!
    var locale : String!
    var loginViewController : LoginViewController!
    var isUserTimedOut = false
    var connectListener : ReadyAppsConnectListener!
    var isLogoutSuccess = false
    
    /**
    Init method that sets up caching for the applicaiton as well as other backend services
    */
    override init() {
        _ = NSHTTPCookieStorage.sharedHTTPCookieStorage();
        
        let cacheMemorySize = 8 * 1024 * 1024;
        let cacheDiskSize = 32 * 1024 * 1024;
        
        let sharedCache = NSURLCache(memoryCapacity: cacheMemorySize, diskCapacity: cacheDiskSize, diskPath: "nsurlcache");
        
        NSURLCache.setSharedURLCache(sharedCache);
      
        super.init();
    }
    
    func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject: AnyObject]?) -> Bool {
        // Set the logger level for MFP
        OCLogger.setLevel(OCLogger_FATAL)
        
        // Do any additional setup after loading the view.
        print("Connecting to MobileFirst Server...");
        connectListener = ReadyAppsConnectListener()
        
        // Connect to MobileFirst server
        WLClient.sharedInstance().wlConnectWithDelegate(connectListener)
        
        // Register authentication challenge handlers
        self.challengeHandler = ReadyAppsChallengeHandler()
        WLClient.sharedInstance().registerChallengeHandler(self.challengeHandler)
        
        // Configure tracker from GoogleService-Info.plist.
        var configureError:NSError?
        GGLContext.sharedInstance().configureWithError(&configureError)
        assert(configureError == nil, "Error configuring Google services: \(configureError)")
        
        // Optional: configure GAI options.
        let gai = GAI.sharedInstance()
        gai.trackUncaughtExceptions = true  // report uncaught exceptions
       
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "handleLoginViewController:", name: "loginVCKey", object: nil)
        return true
    }
    
    func application(application: UIApplication, supportedInterfaceOrientationsForWindow window: UIWindow?) -> UIInterfaceOrientationMask {
        let presentedViewController = window?.rootViewController?.presentedViewController
        
        // All this disables rotation on all views except on the video player view controller for better video viewing
        if let presented = presentedViewController {
            let classString = NSStringFromClass(presented.classForCoder)
            if classString == "AVFullScreenViewController" {
                UIApplication.sharedApplication().setStatusBarHidden(false, withAnimation: UIStatusBarAnimation.None)
                return UIInterfaceOrientationMask.AllButUpsideDown
            }
        }
        return UIInterfaceOrientationMask.Portrait
    }
    
    func handleLoginViewController(notification: NSNotification){
        let userInfo:Dictionary<String,UIViewController!> = notification.userInfo as! Dictionary<String,UIViewController!>
        self.loginViewController = userInfo["LoginViewController"] as! LoginViewController
        
    }
    
    /**
    This method creates a secure tunnel between the client and the server, so the user can be authenticated
    
    - parameter username: of the user
    - parameter password: provided by the user
    */
    func submitAuthentication(username : String, password : String, locale : String){
        self.username = username
        self.password = password
        self.locale = locale
        let adapterName : String = "HealthcareAdapter"
        let procedureName : String = "submitAuthentication"
        let loginInvocationData = WLProcedureInvocationData(adapterName: adapterName, procedureName: procedureName)
        loginInvocationData.parameters = [ username, password, locale]
        self.challengeHandler.submitAdapterAuthentication(loginInvocationData, options: nil)
        
    }
    
    
    /**
    This method handles the opening of a URL when from another iOS application.
    Calls a javascript openURL method in order to work with hybrid view
    
    - parameter application: The singleton app object
    - parameter url:         An object representing a URL
    
    - returns: true if delegate handled URL correctly, false if otherwise
    */
    func application(application: UIApplication, handleOpenURL url: NSURL) -> Bool {
        let jsString = "handleOpenURL(\"\(url)\");";
        self.viewController?.webView.stringByEvaluatingJavaScriptFromString(jsString)
        
        let notification = NSNotification(name: "IBMMILNotification", object: url)
        NSNotificationCenter.defaultCenter().postNotification(notification)
        
        return true;
    }
    
    func application(application: UIApplication, didReceiveLocalNotification notification: UILocalNotification) {
        NSNotificationCenter.defaultCenter().postNotificationName("IBMMILNotification", object: notification)
    }
    
    func applicationDidReceiveMemoryWarning(application: UIApplication) {
        NSURLCache.sharedURLCache().removeAllCachedResponses()
    }
    
    func applicationWillResignActive(application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
    }
    
    func applicationDidEnterBackground(application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
        
    }
    
    func applicationWillEnterForeground(application: UIApplication) {
        // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
    }
    
    func applicationDidBecomeActive(application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }
    
    func applicationWillTerminate(application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
        self.logout("SingleStepAuthRealm")
    }
    
    func logout(realm : String){
        WLClient.sharedInstance().logout(realm, withDelegate: ReadyAppsLogoutListener())
    }
    
    // MARK: - Core Data stack
    
    lazy var applicationDocumentsDirectory: NSURL = {
        // The directory the application uses to store the Core Data store file. This code uses a directory named "com.ibm.mil.ReadyAppPT" in the application's documents Application Support directory.
        let urls = NSFileManager.defaultManager().URLsForDirectory(.DocumentDirectory, inDomains: .UserDomainMask)
        return urls[urls.count-1] 
        }()
    
    lazy var managedObjectModel: NSManagedObjectModel = {
        // The managed object model for the application. This property is not optional. It is a fatal error for the application not to be able to find and load its model.
        let modelURL = NSBundle.mainBundle().URLForResource("Healthcare", withExtension: "momd")!
        return NSManagedObjectModel(contentsOfURL: modelURL)!
        }()
    
    lazy var persistentStoreCoordinator: NSPersistentStoreCoordinator? = {
        // The persistent store coordinator for the application. This implementation creates and return a coordinator, having added the store for the application to it. This property is optional since there are legitimate error conditions that could cause the creation of the store to fail.
        // Create the coordinator and store
        var coordinator: NSPersistentStoreCoordinator? = NSPersistentStoreCoordinator(managedObjectModel: self.managedObjectModel)
        let url = self.applicationDocumentsDirectory.URLByAppendingPathComponent("Healthcare.sqlite")
        var error: NSError? = nil
        var failureReason = "There was an error creating or loading the application's saved data."
        do {
            try coordinator!.addPersistentStoreWithType(NSSQLiteStoreType, configuration: nil, URL: url, options: nil)
        } catch var error1 as NSError {
            error = error1
            coordinator = nil
            // Report any error we got.
            var dict = [NSObject : AnyObject]()
            dict[NSLocalizedDescriptionKey] = "Failed to initialize the application's saved data"
            dict[NSLocalizedFailureReasonErrorKey] = failureReason
            dict[NSUnderlyingErrorKey] = error
            error = NSError(domain: "YOUR_ERROR_DOMAIN", code: 9999, userInfo: dict)
            // Replace this with code to handle the error appropriately.
            // abort() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
            NSLog("Unresolved error \(error), \(error!.userInfo)")
            abort()
        } catch {
            fatalError()
        }
        
        return coordinator
        }()
    
    lazy var managedObjectContext: NSManagedObjectContext? = {
        // Returns the managed object context for the application (which is already bound to the persistent store coordinator for the application.) This property is optional since there are legitimate error conditions that could cause the creation of the context to fail.
        let coordinator = self.persistentStoreCoordinator
        if coordinator == nil {
            return nil
        }
        var managedObjectContext = NSManagedObjectContext()
        managedObjectContext.persistentStoreCoordinator = coordinator
        return managedObjectContext
        }()
    
    // MARK: - Core Data Saving support
    
    func saveContext () {
        if let moc = self.managedObjectContext {
            var error: NSError? = nil
            if moc.hasChanges {
                do {
                    try moc.save()
                } catch let error1 as NSError {
                    error = error1
                    // Replace this implementation with code to handle the error appropriately.
                    // abort() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
                    NSLog("Unresolved error \(error), \(error!.userInfo)")
                    abort()
                }
            }
        }
    }
}