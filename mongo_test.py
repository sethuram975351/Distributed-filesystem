from pymongo import MongoClient
from bson import json_util
import sys
# client = MongoClient("localhost",27222)
# print(client.database_names())
# db = client.USEHASKELLDB

# cursor = db.Directory_RECORD.find({})
# for document in cursor:
#         print(document)
# print("filservers")
# cursor = db.DirHealth_RECORD.find({})
# for document in cursor:
#         print(document)
# cursor = db.Files_RECORD.find({})
# for document in cursor:
#         print(document)
        


# client = MongoClient("localhost",27890)
# print(client.database_names())
# db = client.USEHASKELLDB

# cursor = db.LockService_RECORD.find({})
# for document in cursor:
#         print(document)

# print("client record")
def print_contents():

	allports = {"authserver": 27000,"directoryservice":27222 ,"lock": 27890,"fileserver_0":27090, "fileserver_1": 27091, "fileserver_2":27092, "transactionservice":27984}
	for x in allports:      
		print("printing contents from " + x)
		client = MongoClient("localhost",allports[x])

		
		db = client.USEHASKELLDB
		for collection in db.collection_names()[:-1]:
			print("collection: " + collection)
		
		
			cursor = db[collection].find({})
			for document in cursor:
				print(document)
		print("\n \n \n")
	print("\n checking client1 db")
	client = MongoClient("localhost",27223)   
	db = client.USEHASKELLDB
	for collection in db.collection_names():
		print("collection: " + collection)
		cursor = db[collection].find({})
		for document in cursor:
			print(document)
 
def drop_all():
	"""
		This drops all the contents including directory services'
		As a result fileserver registration will also be deleted 
		and there wont be any filserver information
	"""
	allports = {"authserver": 27000,"directoryservice":27222 ,"lock": 27890,"fileserver_0":27090, "fileserver_1": 27091, "fileserver_2":27092, "transactionservice":27984}
	for x in allports:      
		 
		client = MongoClient("localhost",allports[x]) 
		
		db = client.USEHASKELLDB
		for collection in db.collection_names()[:-1]:
			print(" Droppingcollection: " + collection)
		
		
			cursor = db[collection].drop()
		 
 
# cursor = db.jobs.find({"completed": False,})
# print("\n \n \n")
# for document in cursor:
#         print(document)
# print(db.jobs.find({}).count())
# print("left to do {}". format(list(db.jobs.find({"completed": False,}))))
# print("left to do {}". format(db.jobs.find({"completed": False,}).count()))

# res = db.jobs.aggregate([ 
#     { "$group": { "_id": {},"max": { "$max": "$assigned_time" },"min": { "$min": "$assigned_time" } 
#     }}
# ])
# print(list(res)) 
if __name__=="__main__":
	if len(sys.argv) <2:
		print_contents()
	else:
		drop_all()