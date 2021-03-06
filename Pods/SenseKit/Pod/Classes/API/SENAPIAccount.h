
#import <Foundation/Foundation.h>
#import "SENAPIClient.h"

extern NSString* const kSENAccountNotificationAccountCreated;

@class SENAccount;

@interface SENAPIAccount : NSObject

/**
 *  Create a new account via the Sense API. Does not require authentication.
 *
 *  @param name            full name of the new user
 *  @param emailAddress    email address
 *  @param password        password
 *  @param completionBlock block invoked when asynchonous call completes
 */
+ (void)createAccountWithName:(NSString*)name
                 emailAddress:(NSString*)emailAddress
                     password:(NSString*)password
                   completion:(SENAPIDataBlock)completionBlock;

/**
 * Override the existing account information for the associated user.
 * 
 * Requires authentication.
 *
 * @param account    existing account for the user
 * @param completion block invoked when asynchronous call completes
 */
+ (void)updateAccount:(SENAccount*)account
      completionBlock:(SENAPIDataBlock)completion;

/**
 * Get an instance of a SENAccount object for the currently authorized user.
 * If the user is not authorized / signed in, the object will be nil
 *
 * @param completion block invoked when asynchronous call completes
 */
+ (void)getAccount:(SENAPIDataBlock)completion;

@end
