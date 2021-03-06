
//
//  CacheManager.m
//  Tasit
//
//  Created by Mortgy on 06/02/15.
//  Copyright (c) 2015 mortgy.com. All rights reserved.
//

#import "MGCacheManager.h"

#define DOCUMENTS_DIRECTORY_PATH [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject]
#define CACHE_DIRECTORY_NAME @"cache"
#define CACHE_SALT_KEY @"mgCacheSalt-"

#define MGCACHE_MINUTE_IN_SECONDS 60

#pragma mark - functions

extern BOOL isNull(id value)
{
	if (!value) return YES;
	if ([value isKindOfClass:[NSNull class]]) return YES;
	
	return NO;
}

@implementation MGCacheManager

+ (BOOL)validateCachedFileExistanceForKey:(NSString *)fileNameKey {
	
	fileNameKey = [NSString stringWithFormat:@"%@%@", CACHE_SALT_KEY, fileNameKey];
	
	NSString * path = [DOCUMENTS_DIRECTORY_PATH stringByAppendingPathComponent:[NSString stringWithFormat:@"/%@/%@",CACHE_DIRECTORY_NAME,fileNameKey]];
	
	NSFileManager *fileManager = [NSFileManager defaultManager];
	
	if ([fileManager fileExistsAtPath:path]) {
		
		NSDictionary* fileAttribs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
		NSDate *fileCreationDate = [fileAttribs objectForKey:NSFileCreationDate];
		NSDate *expirationDate = [fileCreationDate dateByAddingTimeInterval:+MGCACHE_MINUTE_IN_SECONDS*[self findExpirationPeriodOfKey:fileNameKey]];
		
		if ([expirationDate compare:[NSDate dateWithTimeIntervalSinceNow:0]] == NSOrderedAscending) {
			
			[self deleteCachedFileForFileNameKey:fileNameKey];
			
			return NO;
		}
		else {
			return YES;
		}
	}
	
	return NO;
}

+ (NSUInteger)findExpirationPeriodOfKey:(NSString *)key {
	NSNumber *cachePeriod = [[NSUserDefaults standardUserDefaults] valueForKey:key];
	if (cachePeriod) {
		return [cachePeriod intValue];
	}
	return -1;
}

+(void)asyncSaveAndReturnKeyResponse:(id)response
								 key:(NSString *)key
						 cachePeriod:(NSNumber *)cachePeriod{
	
	dispatch_queue_t apiQueue = dispatch_queue_create("ApiQueue",NULL);
	dispatch_async(apiQueue, ^{
		[self saveAndReturnKeyResponse:response key:key cachePeriod:cachePeriod];
	});
}

+(id)saveAndReturnKeyResponse:(id)response
						  key:(NSString *)key
				  cachePeriod:(NSNumber *)cachePeriod {
	
	[self createDirectoryForCaches];
	
	NSData *data = [NSKeyedArchiver archivedDataWithRootObject:response];
	key = [NSString stringWithFormat:@"%@%@", CACHE_SALT_KEY, key];
	
	if (cachePeriod) {
		[[NSUserDefaults standardUserDefaults] setValue:cachePeriod forKey:key];
	}
	
	if (data) {
		NSString * path = [DOCUMENTS_DIRECTORY_PATH stringByAppendingPathComponent:[NSString stringWithFormat:@"/%@/%@",CACHE_DIRECTORY_NAME, key]];
		[data writeToFile:path atomically:YES];
	}
	
	return response;
}

+ (id)loadDataFromCacheFileNameKey:(NSString *)fileNameKey  {
	
	if ([self validateCachedFileExistanceForKey:fileNameKey]) {
		fileNameKey = [NSString stringWithFormat:@"%@%@", CACHE_SALT_KEY, fileNameKey];
		NSData *data = [[NSData alloc] initWithContentsOfFile:[DOCUMENTS_DIRECTORY_PATH stringByAppendingPathComponent:[NSString stringWithFormat:@"/%@/%@",CACHE_DIRECTORY_NAME, fileNameKey]]];
		
		data = [NSKeyedUnarchiver unarchiveObjectWithData:data];
		return data;
	} else {
		return nil;
	}
}

+ (void)createDirectoryForCaches {
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSString *folderName = [DOCUMENTS_DIRECTORY_PATH stringByAppendingPathComponent:CACHE_DIRECTORY_NAME];
	if (![fileManager fileExistsAtPath:folderName]) {
		[fileManager createDirectoryAtPath:folderName withIntermediateDirectories:NO attributes:nil error:nil];
	}
}

+ (void)cleanExpiredCaches {
	
	NSArray * expirableCacheKeys = [[[NSUserDefaults standardUserDefaults] dictionaryRepresentation] allKeys];
	expirableCacheKeys = [self array:expirableCacheKeys select:^BOOL(NSString * object) {
		return ([object containsString:CACHE_SALT_KEY]);
	}];
	
	for (NSString *fileNameKey in expirableCacheKeys) {
		
		NSString * path = [DOCUMENTS_DIRECTORY_PATH stringByAppendingPathComponent:[NSString stringWithFormat:@"/%@/%@", CACHE_DIRECTORY_NAME, fileNameKey]];
		NSFileManager *fileManager = [NSFileManager defaultManager];
		
		if ([fileManager fileExistsAtPath:path]){
			
			NSDictionary* fileAttribs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
			NSDate *fileCreationDate = [fileAttribs objectForKey:NSFileCreationDate];
			
			NSDate *expirationDate = [fileCreationDate dateByAddingTimeInterval:+MGCACHE_MINUTE_IN_SECONDS*[self findExpirationPeriodOfKey:fileNameKey]];
						
			if ([expirationDate compare:[NSDate dateWithTimeIntervalSinceNow:0]] == NSOrderedAscending) {
				
				[self deleteCachedFileForFileNameKey:fileNameKey];
			}
		}
	}
}

+ (void)deleteAllCachesBeforeDate:(NSNumber *)unixDate {
	
	NSDate *date = [NSDate dateWithTimeIntervalSince1970:unixDate.doubleValue];
	NSArray *cacheFiles = [[NSFileManager defaultManager] subpathsOfDirectoryAtPath:[NSString stringWithFormat:@"%@/%@", DOCUMENTS_DIRECTORY_PATH,CACHE_DIRECTORY_NAME]  error:nil];
	
	for (NSString *fileName in cacheFiles) {
		NSString *path = [DOCUMENTS_DIRECTORY_PATH stringByAppendingPathComponent:[NSString stringWithFormat:@"/%@/%@",CACHE_DIRECTORY_NAME, fileName]];
		NSFileManager *fileManager = [NSFileManager defaultManager];
		
		if ([fileManager fileExistsAtPath:path]){
			if ([date compare:[NSDate dateWithTimeIntervalSince1970:0]] == NSOrderedAscending) {
				[self deleteCachedFileForFileNameKey:fileName];
			}
		}
	}
	
	[[NSUserDefaults standardUserDefaults] setObject:unixDate forKey:@"latestForcedCacheDeletion"];
}

+ (void)deleteCachedFileForFileNameKey:(NSString *)fileNameKey {
	
	NSString * path = [DOCUMENTS_DIRECTORY_PATH stringByAppendingPathComponent:[NSString stringWithFormat:@"/%@/%@",CACHE_DIRECTORY_NAME, fileNameKey]];
	NSError *error;
	if ([[NSFileManager defaultManager] isDeletableFileAtPath:path]) {
		BOOL success = [[NSFileManager defaultManager] removeItemAtPath:path error:&error];
		!success ? NSLog(@"Error removing file at path: %@", error.localizedDescription) : NSLog(@"File Deleted");
	}
}

+ (void)deleteCachedFileForKey:(NSString *)key {

	NSString * path = [DOCUMENTS_DIRECTORY_PATH stringByAppendingPathComponent:[NSString stringWithFormat:@"/%@/%@%@",CACHE_DIRECTORY_NAME, CACHE_SALT_KEY, key]];
	NSError *error;
	if ([[NSFileManager defaultManager] isDeletableFileAtPath:path]) {
		BOOL success = [[NSFileManager defaultManager] removeItemAtPath:path error:&error];
		!success ? NSLog(@"Error removing file at path: %@", error.localizedDescription) : NSLog(@"File Deleted");
	}
}

+ (NSString*)buildKey:(NSDictionary*)params {
	NSMutableString *key = [NSMutableString new];
	for (NSString *paramKey in params) {
		if (!isNull(params[paramKey])) {
			[key appendString:[NSString stringWithFormat:@"-%@-%@", paramKey, params[paramKey]]];
		}
	}
	
	return [key copy];
}

+ (NSArray *)array:(NSArray *)sourceArray select:(BOOL (^)(id object))block {
	NSMutableArray *array = [NSMutableArray arrayWithCapacity:sourceArray.count];
	
	for (id object in sourceArray) {
		if (block(object)) {
			[array addObject:object];
		}
	}
	
	return array;
}

@end
