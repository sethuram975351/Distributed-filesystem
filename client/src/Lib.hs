{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE TemplateHaskell       #-}
{-# LANGUAGE DataKinds            #-}
{-# LANGUAGE DeriveAnyClass       #-}
{-# LANGUAGE DeriveGeneric        #-}
{-# LANGUAGE FlexibleContexts     #-}
{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE OverloadedStrings    #-}
{-# LANGUAGE StandaloneDeriving   #-}
{-# LANGUAGE TemplateHaskell      #-}
{-# LANGUAGE TypeOperators        #-}
{-# LANGUAGE TypeSynonymInstances #-}
module Lib
    ( someFunc

    ) where
import           Control.Concurrent           (forkIO, threadDelay)
import           System.IO
import           Control.Monad                 
import           Control.Monad.IO.Class
import           Control.Monad.Trans.Except   (ExceptT)
import           Control.Monad.Trans.Resource
import           Data.Bson.Generic 
import           Distribution.PackageDescription.TH
import           Git.Embed
import           Network.HTTP.Client          (defaultManagerSettings,newManager)

import           Network.Wai
import           Network.Wai.Handler.Warp
import           Network.Wai.Logger
import           Servant
import qualified Servant.API                  as SC
import qualified Servant.Client               as SC
import           System.Console.ANSI
import           System.Environment
import qualified FilesystemAPI as FSA  
import           FilesystemAPIClient 
import           Data.Time.Clock
import qualified Data.List                    as DL
import           Database.MongoDB       
import           Data.Maybe
import           GHC.Generics
import           Data.Text                    (pack, unpack)
import           Datatypes 
import           EncryptionAPI
import           Helpers        
import           Data.List.Split
import           Data.Char 
import           Datatypes

import           System.Log.Formatter
import           System.Log.Handler           (setFormatter)
import           System.Log.Handler.Simple
import           System.Log.Handler.Syslog
import           System.Log.Logger
-- write to db
-- sleep and read from db
-- 

type API1 =  "lockAvailable"         :> ReqBody '[JSON] LockTransfer  :> Post '[JSON] Bool
 

startApp :: IO ()    -- set up wai logger for service to output apache style logging for rest calls
startApp = FSA.withLogging $ \ aplogger -> do 
  FSA.warnLog "Starting client"

  let settings = setPort 8050 $ setLogger aplogger defaultSettings
  forkIO $ menu  
  runSettings settings app


app :: Application
app = serve api server

api :: Proxy API1
api = Proxy

-- | And now we implement the REST service by matching the API type, providing a Handler method for each endpoint
-- defined in the API type. Normally we would implement each endpoint using a unique method definition, but this need
-- not be so. To add a news endpoint, define it in type API above, and add and implement a handler here.
server :: Server API1
server = lockAvailable
  where
    lockAvailable :: LockTransfer -> Handler Bool
    lockAvailable lockdetails@(LockTransfer filepath _ ) =  liftIO $ do 
      withMongoDbConnectionForClient $ upsert (select ["filepathq" =: filepath] "LockAvailability_RECORD") $ toBSON $ lockdetails
      return True


{-
    Checks every 10 seconds if the client is allocated a lock
-}

islockAvailable :: String ->  IO (Bool)
islockAvailable  filepath = liftIO $ do
  docs <- withMongoDbConnectionForClient $ find  (select ["filepathq" =: filepath] "Transaction_RECORD")  >>= FSA.drainCursor 
  let  lock= take 1 $ catMaybes $ DL.map (\ b -> fromBSON b :: Maybe LockTransfer) docs 
  case lock of 
    ([LockTransfer _ True]) -> do 
      putStrLn "CLIENT: LOCK AVAILABLE YAY!!"
      return True
    ([LockTransfer _ False] ) -> do 
      putStrLn "CLIENT: Going to sleep as lock is not available"
      threadDelay $ 10 * 1000000
      islockAvailable filepath 
    otherwise  -> do 
      putStrLn "CLIENT: Lock details are not available locally"
      return False
  
  
-- Locking file
---------------------------------------------------
 
doFileLock :: String-> String -> IO ()
doFileLock fpath usern= do
  authInfo <- getAuthClientInfo usern
  case authInfo of 
    (Just (ticket,seshkey) ) -> do 
      let encFpath = myEncryptAES (aesPad seshkey) (fpath)
      let encUname = myEncryptAES (aesPad seshkey) (usern)
      doCall  (lock $ Message3  encFpath encUname ticket) FSA.lockIP FSA.lockPort seshkey

    (Nothing) -> putStrLn $ "Expired token . Sigin in again.  " 
  

doFileUnLock :: String-> String -> IO ()
doFileUnLock fpath usern= do
  authInfo <- getAuthClientInfo usern
  case authInfo of 
    (Just (ticket,seshkey) ) -> do 
      let encFpath = myEncryptAES (aesPad seshkey) (fpath)
      let encUname = myEncryptAES (aesPad seshkey) (usern)
      doCall (unlock  $ Message3 encFpath encUname ticket) FSA.lockIP FSA.lockPort seshkey
    (Nothing) -> putStrLn $ " Expired token  .Sigin in again. " 

doIsLocked :: String  ->  IO ()
doIsLocked fpath  = doCall (islocked $ Just fpath) FSA.lockIP FSA.lockPort $  seshNop
---------------------------------
-- Directory services
---------------------------------

 

  
doListDirs :: String -> IO ()
doListDirs usern=  do 
  authInfo <- getAuthClientInfo usern
  case authInfo of 
    (Just (ticket,seshkey) ) -> do 
      doCall (listdirs $ Just ticket) FSA.dirHost FSA.dirPort seshkey
    (Nothing) -> putStrLn $ "Expired token . Sigin in again.  " 
   --  FSA.dirPort in filesystem api

doLSFileServerContents :: String  -> String -> IO ()
doLSFileServerContents dir usern=docallMsg1WithEnc listfscontents dir usern FSA.dirHost FSA.dirPort 



doFileSearch :: String -> String -> String -> IO ()
doFileSearch dir fname usern = docallMsg3WithEnc  filesearch dir fname usern FSA.dirHost FSA.dirPort
 

-----------------------------
-- Transaction service
-----------------------------
-- client can only do one transaction at a time     
-- Checks the database if there is an transaction running, it would abort and continue with new transaction  
doGetTransId :: String-> IO ()
doGetTransId usern=  do
  res <-  mydoCalMsg1WithEnc getTransId usern ((read $ FSA.transPorStr):: Int)
  case res of
    Nothing ->   putStrLn $ "get file call to fileserver  failed with error: "  
    Just (ResponseData enctrId) -> do 
 

      authInfo <- getAuthClientInfo usern
      case authInfo of 
        (Just (ticket,seshkey) ) -> do
          let trId =  myDecryptAES (aesPad seshkey)  (enctrId)
           
          let key = "client1":: String --- maybe an environment variable in the docker compose
          docs <- withMongoDbConnectionForClient $ find  (select ["key1" =: key] "Transaction_RECORD")  >>= FSA.drainCursor -- getting previous transaction id of the client
          let  clientTrans= take 1 $ catMaybes $ DL.map (\ b -> fromBSON b :: Maybe LocalTransInfo) docs 
          case clientTrans of 
            [LocalTransInfo _  prevId] -> liftIO $ do  -- abort and update
                putStrLn $ "Aborting old transaction and starting new " 
      
                docallMsg1WithEnc abort prevId usern FSA.transIP FSA.transPort
                
              
                withMongoDbConnectionForClient $ upsert (select ["key1" =: key] "Transaction_RECORD") $ toBSON $ LocalTransInfo key trId -- store the transaction id
            [] -> liftIO $ do 
              putStrLn $ "Starting new transaction " ++trId
              withMongoDbConnectionForClient $ upsert (select ["key1" =: key] "Transaction_RECORD") $ toBSON $ LocalTransInfo key trId -- store the transaction id
 
        (Nothing) -> putStrLn $ " Expired token  .Sigin in again. " 
      
 
     
doCommit :: String -> IO ()
doCommit usern = do 
  localTransactionInfo <- getLocalTrId
  case localTransactionInfo of        
    [ LocalTransInfo _ trId] -> liftIO $ do  
      docallMsg1WithEnc commit trId usern FSA.transIP FSA.transPort 
      unlockLockedFiles trId usern
      clearTransaction-- clearing after commiting the transaction
    [] -> putStrLn "No transactions to  commit"

doAbort :: String -> IO ()
doAbort usern  = do 
  localTransactionInfo <- getLocalTrId
  case localTransactionInfo of 
    [LocalTransInfo _ trId] -> liftIO $ do   
      docallMsg1WithEnc abort trId usern FSA.transIP FSA.transPort
      unlockLockedFiles trId usern
      clearTransaction -- clearing after aborting the transaction
    [] -> putStrLn "No transactions to  abort"
-- localfilePath : file path in the client
-- dir           : fileserver name
-- fname         : filename 

doUploadWithTransaction:: String-> String -> String ->  String -> IO ()
doUploadWithTransaction localfilePath  dir fname  usern = do
  localTransactionInfo <- getLocalTrId 
  --  Client will just tell the where they want to store the file 
  -- transaction has to figure out the file info and update directory info  
  let filepath=  dir ++fname
  status <- isFileLocked filepath
  case status of  --- if the file is locked it cannot be added to the transaction
    (False) -> do
      case localTransactionInfo of  -- get local transaction info
        [LocalTransInfo _ trId] -> liftIO $ do     
          contents <- readFile localfilePath
          let filepath = dir++fname
          

          doFileLock filepath usern -- lock the file
          appendToLockedFiles filepath trId -- list of locked files which the client keeps a record of
          res <- mydoCalMsg4WithEnc uploadToShadowDir dir fname trId usern ((read $ FSA.dirServPort):: Int) decryptFInfoTransfer -- uploading info to shadow directory
          --res <- FSA.mydoCall (uploadToShadowDir $  Message3 dir fname trId ) ((read $ fromJust FSA.dirPort):: Int) -- uploading info to shadow directory

          case res of
            Nothing -> putStrLn $ "Upload to transaction failed"  
            Just (a) ->   do 
              case a of 
                ([fileinfotransfer @(FInfoTransfer _ _ fileid _ _ _ )]) -> do
                  let filecontents=FileContents fileid  contents ""
                
                  let transactionContent=TransactionContents trId (TChanges fileinfotransfer filecontents ) ""
                  
                  --- encrypting transaction information before uploading
                  authInfo <- getAuthClientInfo usern
                  case authInfo of 
                    (Just (ticket,seshkey) ) -> do 
                      let msg = encryptTransactionContents transactionContent seshkey ticket
                       
                      doCall (uploadToTransaction $ msg) FSA.transIP FSA.transPort $  seshNop
                    (Nothing) -> putStrLn $ " Expired token  .Sigin in again. " 
                [] -> putStrLn "doUploadWithTransaction: Error getting fileinfo "


          -- call the directory service get info 
          
        [] -> putStrLn "No ongoing transaction"

    (True) -> putStrLn "File is locked"


---------------------------------

{-
  doWriteFileworkflow
  1.check if the file is locked
  2.if not send the file metadata to the directory service
  3.Lock the file
  4.Update file local copy 
  5.Encrypt the contents and send it to the fileserver 
-}


doWriteFile::  String  -> String ->  String -> IO ()
doWriteFile  remoteFPath usern newcontent = do   -- call to the directory server saying this file has been updated 
  
  let remotedir =head $ splitOn "/" remoteFPath
      fname = last $ splitOn "/" remoteFPath  
      localfilePath = "./" ++ fname
  
  state <- isFileLocked remoteFPath  
  case state of 
    (False) -> do 
      
        
        res <- mydoCalMsg3WithEnc updateUploadInfo remotedir fname usern ((read FSA.dirServPort):: Int) decryptFInfoTransfer
        case res of
          Nothing -> putStrLn $ "Upload file failed call failed " 
          (Just a) ->   do 
            case a of 
              [(fileinfotransfer@(FInfoTransfer _ _ fileid h p ts ))] -> do   
                case  p =="none" of
                  (True)->  putStrLn "Upload failed : No fileservers available."
                  (False)-> do
                    doFileLock remoteFPath usern -- lock file before storing
                    putStrLn $ "Recieved file lock" 
                    -- update local file and push the changes up
                    


                    appendFile localfilePath $ newcontent
                    contents <- readFile localfilePath

                    authInfo <- getAuthClientInfo usern
                    case authInfo of 
                      (Just (ticket,seshkey) ) -> do 
                        let msg = encryptFileContents  (FileContents fileid contents "") seshkey ticket -- encrypted message
                        doCall (upload  msg) (Just h) (Just p)  seshkey -- uploading file
                        doFileUnLock remoteFPath usern
                        -- store the metadata about the file
                        updateLocalMeta remoteFPath $ FInfo remoteFPath remotedir fileid ts
                        putStrLn "file unlocked "
                      (Nothing) -> putStrLn $ "Expired token . Sigin in again.  "  
              [] -> putStrLn "Upload file : Error getting fileinfo from directory service"

         
    (True) -> putStrLn "File is locked"

-- client



-- filepath :- id fileserver'
-- dir has to be the name
-- fname    : filename
 
displayFile :: String -> IO ()
displayFile filepath = do
  putStrLn $ "Printing contents of the file"
  handle <- openFile filepath ReadMode
  contents <- hGetContents handle
  print contents
  hClose handle   

 

doReadFile :: String -> String-> IO ()
doReadFile remoteFPath usern = do 
  -- talk to the directory service to get the file details
  let remotedir =head $ splitOn "/" remoteFPath
      fname = last $ splitOn "/" remoteFPath
  res <- mydoCalMsg3WithEnc filesearch remotedir fname usern ((read FSA.dirServPort):: Int) decryptFInfoTransfer
  case res of
    Nothing ->  putStrLn $ "download call failed" 
    (Just fileinfo@resp) ->   do 
      case resp of
        [FInfoTransfer filepath dirname fileid ipadr portadr servTm1 ] -> do 
          putStrLn $ portadr ++ "file id "++ fileid

          status <- isDated filepath servTm1  --check with timestamp in the database 
          case status of
            True ->  getFileFromFS  fileinfo usern -- it also updates local file metadata
            False -> putStrLn "You have most up to date  version" 
          displayFile fname
        [] -> putStrLn " The file might not be in the fileserver directory" 
        
      
 

-- gets the public key of the auth server and encrypts message and sends it over 
doSignup:: String -> String -> IO ()
doSignup userN pass =  do
  resp <- FSA.mydoCall (loadPublicKey) ((read FSA.authPortStr):: Int)
  case resp of
    Left err -> do
      putStrLn $ "failed to get public key... " ++  show err
    Right ((ResponseData a):(ResponseData b):(ResponseData c):rest) -> do
      let authKey = toPublicKey (PubKeyInfo a b c)
      cryptPass <- encryptPass authKey pass
      putStrLn "got the public key!"
      
      doCall (signup $ UserInfo userN cryptPass) FSA.authIP FSA.authPort $  seshNop
      putStrLn "Sent encrypted username and password to authserver"


doLogin:: String -> String-> IO ()
doLogin userN pass  = do
  resp <- FSA.mydoCall (loadPublicKey) ((read FSA.authPortStr):: Int)
  case resp of
    Left err -> do
      putStrLn "failed to get public key..."
    Right ((ResponseData a):(ResponseData b):(ResponseData c):rest) -> do
      let authKey = toPublicKey (PubKeyInfo a b c)
      cryptPass <- encryptPass authKey pass
      putStrLn "got the public key!"
      mydoCall2  (storeClientAuthInfo userN pass) (login $ UserInfo userN cryptPass) ((read FSA.authPortStr):: Int)
      putStrLn "Sending client info (pass and username) to authserver"
      

-- First we invoke the options on the entry point.
someFunc :: IO ()
someFunc = do 
    menu



menu = do
  contents <- getLine 
  if DL.isPrefixOf "login" contents
    then do
      let cmds =  splitOn " " contents
      --"User name" password"
      doLogin (cmds !! 1) (cmds !! 2)
  else if DL.isPrefixOf  "signup" contents
    then do
      let cmds =  splitOn " " contents
      --"User name" password"
      doSignup  (cmds !! 1) (cmds !! 2)
  else if DL.isPrefixOf  "readfile" contents
    then do
      let cmds =  splitOn " " contents
      -- "remote dir/fname (filepath)"    "username"
      doReadFile  (cmds !! 1) (cmds !! 2) 
  else if DL.isPrefixOf  "write" contents
    then do
      let cmds =  splitOn " " contents
      -- "remote dir/fname (filepath)" "user name" "content to add"
      doWriteFile  (cmds !! 1) (cmds !! 2) (cmds !! 3)  
  else if DL.isPrefixOf  "lockfile" contents
    then do
      let cmds =  splitOn " " contents
      -- "remote dir/filename"   "user name"
      doFileLock  (cmds !! 1) (cmds !! 2) 
  else if DL.isPrefixOf  "unlockfile" contents
    then do
      let cmds =  splitOn " " contents
      -- "remote dir/filename"   "user name"
      doFileUnLock  (cmds !! 1) (cmds !! 2) 
  else if DL.isPrefixOf  "listdirs" contents
    then do
      let cmds =  splitOn " " contents
      --   "user name"
      doListDirs  (cmds !! 1) 
  else if DL.isPrefixOf  "lsdircontents" contents
    then do
      let cmds =  splitOn " " contents
      --   "remote dir/filename" "user name"
      doLSFileServerContents  (cmds !! 1)    (cmds !! 2) 
  else if DL.isPrefixOf  "filesearch" contents
    then do
      let cmds =  splitOn " " contents
      --  "remote dir"  "remote dir/filename"   "user name"
      doFileSearch  (cmds !! 1) (cmds !! 2) (cmds !! 3) 

  else if DL.isPrefixOf  "startTrans" contents
    then do
      let cmds =  splitOn " " contents
      --    "user name"
      doGetTransId  (cmds !! 1) 
  else if DL.isPrefixOf  "commit" contents
    then do
      let cmds =  splitOn " " contents
      --    "user name"
      doCommit  (cmds !! 1) 
  else if DL.isPrefixOf  "abort" contents
    then do
      let cmds =  splitOn " " contents
      --    "user name"
      doAbort  (cmds !! 1) 
  else if DL.isPrefixOf  "writeT" contents
    then do
      let cmds =  splitOn " " contents
     -- "local file path" "remote dir" "file name" "user name"
      doUploadWithTransaction  (cmds !! 1) (cmds !! 2) (cmds !! 3) (cmds !! 4)
  else
    putStrLn $"no command specified"
  menu


unlockLockedFiles :: String  -> String -> IO() 
unlockLockedFiles  tid  usern= liftIO $ do
   docs <- withMongoDbConnectionForClient $ find (select ["tid5" =: tid] "LockedFiles_RECORD") >>= FSA.drainCursor
   let  contents= take 1 $ catMaybes $ DL.map (\ b -> fromBSON b :: Maybe LockedFiles) docs 
   case contents of 
    [] -> return ()
    [LockedFiles _ files] -> do -- adding to existing transaction 
      foldM (\ a filepath -> doFileUnLock filepath usern) () files
      withMongoDbConnectionForClient $ delete (select ["tid5" =: tid] "LockedFiles_RECORD")  
