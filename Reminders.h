//
//  Reminders.h
//  Venus
//
//  Created by Kevin O' Sullivan on 05/02/2015.
//  Copyright (c) 2015 ITGS Labs. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "NurseProgressVisit.h"
#import "NarrativeRemindersLogicClass.h"
#import "VenusCoreDataModel.h"
#import "Utilities.h"
#import "Wounds.h"

@interface Reminders : NSObject

/**
 *  @author Kevin O  Sullivan
 *  
 *  A custom init method wich accepts a visit object. This class must be invoke using this initializer. The idea is to use this class for any visit type that requires reminders
 *
 *
 *  @param visit The visit object
 *
 *  @return self id
 */
-(id)initWithVisit:(id)visit;

/**
 *  @author Kevin O  Sullivan
 *  
 *  Generates Reminders for an NPN
 *  This method requires the _visit property to be of NurseProgressVisit type
 */
-(void)generateRemindersForNPN;

/**
 *  @author Kevin O  Sullivan
 *  
 *  Returns the schema for all the fields that require narrative alerts. It should illustrate the section a field belongs to, the title to be present on the UI and the field type.
 *  This schema is used to figure out how to display the narrative reminders in the UI.
 *
 *  @return NSDictionary containing the fields schema
 */
-(NSDictionary *)getNPNReminderFieldsSchema;

/**
 *  @author Kevin O  Sullivan
 *  
 *  The visit object. It is defaulted as an id type. We can then cast to the appropriate NSManagedObject depending on what visit type we need reminders for.
 */
@property id visit;

/**
 *  @author Kevin O  Sullivan
 *  
 *  An NSDictionary containing the rules needed to generate the reminders
 */
@property NSDictionary *reminderRules;
@end
