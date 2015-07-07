//
//  Reminders.m
//  Venus
//
//  Created by Kevin O' Sullivan on 05/02/2015.
//  Copyright (c) 2015 ITGS Labs. All rights reserved.
//

#import "Reminders.h"

@implementation Reminders


-(id)initWithVisit:(id)visit{
    if ([super init]) {
        if ([visit isKindOfClass:[NurseProgressVisit class]]) {
            _reminderRules = [self readNpnReminderRules];
        }
        
        _visit = visit;
    }
    return self;
}

-(id)init{
    return [self initWithVisit:_visit];
}

-(void)generateRemindersForNPN{

    NurseProgressVisit *visit = (NurseProgressVisit *)_visit;
    NarrativeRemindersLogicClass *reminderObj = [[NarrativeRemindersLogicClass alloc] initWithManagedObjectContext:[self managedObjectContext]];
    
    NSArray *fieldsWithRules = [_reminderRules allKeys];
    NSArray *relationships = @[@"wounds"];
    
    // Just the NPN fields without relationships
    for (NSString *field in fieldsWithRules) {
        if([relationships containsObject:_reminderRules[field]]){
            // If its one of the relationships, skip.
            continue;
        }
        NSArray *rules = _reminderRules[field][@"rules"];

        if([self testField:field forRules:rules forValue:[visit valueForKey:field]]){
            NarrativeReminder *createdReminder = [reminderObj createReminderForVisit:visit withSourceField:field andMessage:_reminderRules[field][@"message"] andSourceEntity:visit.entity.name andParent:nil];
        }
        else{
            // If any rule fails to generate a reminder then we do a little clean up just to make sure that there are no saved reminders for that field
            NSArray *remindersToDelete = [reminderObj getRemindersFromVisit:visit forSourceField:field];
            for (NarrativeReminder *reminderToDelete in remindersToDelete) {
                [reminderObj deleteReminder:reminderToDelete ForVisit:visit];
            }
        }
        
    }
    
    // Build a dictionary of found reminders for the data saved
    NSMutableDictionary *woundsRemDict = [[NSMutableDictionary alloc] init];
    // Wound fields. Loop through the rules
    for (NSString *field in _reminderRules[@"wounds"]) {
        
        // We have to check the rules for every wound so, loop though.
        for (Wounds *wound in visit.wounds) {
            NSArray *rules = _reminderRules[@"wounds"][field][@"rules"];
            
            if([self testField:field forRules:rules forValue:[wound valueForKey:field]]){
                
                [woundsRemDict setObject:@{
                                           @"message":_reminderRules[@"wounds"][field][@"message"],
                                           @"wound": wound,
                                           } forKey:field];
                
                continue;
            }
        }
    }
    
    // Clear out the existing reminders and replace them with the Dictionary of found reminders
    //[reminderObj deleteRemindersForVisit:_visit forSourceEntity:@"Wounds"];
    for (NSString *field in woundsRemDict) {
        NSArray *arr = [reminderObj getRemindersFromVisit:visit forSourceField:field];
        if([arr count] > 0){
            NarrativeReminder *rem = arr[0];
            if(rem.status == nil)
                [reminderObj deleteReminder:arr[0] ForVisit:visit];
        }
        [reminderObj createReminderForVisit:visit withSourceField:field andMessage:woundsRemDict[field][@"message"] andSourceEntity:@"Wounds" andParent:woundsRemDict[field][@"wound"]];
    }
}

/**
 *  @author Kevin O  Sullivan
 *  
 *  Tests a given field for an array of rules
 *
 *  @param field The field to test
 *  @param rules An NSArray of rules to test against
 *  @param value The value of the field to test
 *
 *  @return returns true if a reminder should be generated
 */
-(BOOL)testField:(NSString *)field forRules: (NSArray *)rules forValue:(id)value{
    BOOL fieldShouldGenerateReminder = NO;
    
    // We need to loop through all the rules and test one by one. If any of them should generate a reminder we can break early and return true.

    for (NSDictionary *rule in rules) {
        fieldShouldGenerateReminder = [self testField:field forRule:rule forValue:value];
        if (fieldShouldGenerateReminder) {
            break;
        }
    }
    return fieldShouldGenerateReminder;
}
/**
 *  @author Kevin O  Sullivan
 *  
 *  Tests a given field against one rule
 *
 *  @param field The field to test
 *  @param rule  The rule to test against
 *  @param value The value to test
 *
 *  @return returns true if a reminder should be generated
 */
-(BOOL)testField:(NSString *)field forRule:(NSDictionary *)rule forValue:(id)value{
    
    BOOL fieldShouldGenerateReminder = NO;
    
    if ([rule[@"type"] isEqualToString:@"range"]) {
        fieldShouldGenerateReminder = [self testRangeRule:rule forValue:value];
    }
    else if ([rule[@"type"] isEqualToString:@"bool"]) {
        fieldShouldGenerateReminder = [self testBoolRule:rule forValue:value];
    }
    else if ([rule[@"type"] isEqualToString:@"array_with_any_value"]) {
        fieldShouldGenerateReminder = [self testArrayWithAnyValueRule:rule forValue:value];
    }
    else if ([rule[@"type"] isEqualToString:@"array_contains"]) {
        fieldShouldGenerateReminder = [self testArrayContainsRule:rule forValue:value];
    }
    else if ([rule[@"type"] isEqualToString:@"value_equals"]) {
        fieldShouldGenerateReminder = [self testValueEqualsRule:rule forValue:value];
    }
    else if ([rule[@"type"] isEqualToString:@"days_older_than_today"]) {
        fieldShouldGenerateReminder = [self testDaysOlderThanTodayRule:rule forValue:value];
    }
    else if ([rule[@"type"] isEqualToString:@"string_with_value"]) {
        fieldShouldGenerateReminder = [self testStringWithValueRule:rule forValue:value];
    }
    else if ([rule[@"type"] isEqualToString:@"set_has_objects"]) {
        fieldShouldGenerateReminder = [self testSetHasObjectsRule:rule forValue:value];
    }
    
    return fieldShouldGenerateReminder;
}

#pragma mark - 
#pragma mark Rule Checks

/**
 *  @author Kevin O  Sullivan
 *  
 *  Test if a value falls within a certain range. This method expects a rule that contains the keys "lower_limit" and "upper_limit" to be set with number values
 *
 *  @param rule  The rule to test against
 *  @param value The value to test
 *
 *  @return returns true if a reminder should be generated
 */
-(BOOL)testRangeRule:(NSDictionary *)rule forValue:(id)value{
    
    if (!value) {
        return NO;
    }
    
    CGFloat lowerLimit = [rule[@"lower_limit"] floatValue];
    CGFloat upperLimit = [rule[@"upper_limit"] floatValue];
    
    if ([value floatValue] >= lowerLimit && [value floatValue] <= upperLimit) {
        return YES;
    }
    else
        return NO;
    
    
}

/**
 *  @author Kevin O  Sullivan
 *  
 *  Tests if a value given matches a bool trigger. This method expects the rule to contain a key "trigger" which should be set to either "true" or "false"
 *
 *  @param rule  The rule to test against
 *  @param value The value to test
 *
 *  @return returns true if a reminder should be generated
 */
-(BOOL)testBoolRule:(NSDictionary *)rule forValue:(id)value{
    
    if (!value) {
        return NO;
    }
    
    BOOL trigger = [rule[@"trigger"] boolValue];

    if(trigger == [value boolValue] ){
        return YES;
    }
    else{
        return NO;
    }

}

/**
 *  @author Kevin O  Sullivan
 *  
 *  Tests if a value matches a value specified in the rule. This method expects that the rule contains a key "trigger" which contains a string
 *
 *  @param rule  The rule to test against
 *  @param value The value
 *
 *  @return returns true if a reminder should be generated
 */
-(BOOL)testValueEqualsRule:(NSDictionary *)rule forValue:(id)value{
    
    if (!value) {
        return NO;
    }
    
    NSString *trigger = [rule[@"trigger"] lowercaseString];
    
    if([trigger isEqualToString:[(NSString *)value lowercaseString]] ){
        return YES;
    }
    else{
        return NO;
    }
    
}

/**
 *  @author Kevin O  Sullivan
 *  
 *  Tests if an json array of values contains any value. This method also accepts a key "exception" which is an array of values to ignore.
 *
 *  @param rule  The rule to test against
 *  @param value The json array directly from coredata. eg "[\"test\"]"
 *
 *  @return returns true if a reminder should be generated
 */
-(BOOL)testArrayWithAnyValueRule:(NSDictionary *)rule forValue:(id)value{
    
    if (!value) {
        return NO;
    }
    
    NSMutableArray *valueArray = [[Utilities sharedInstance] jsonArrayToMutableArray:value];
    
    NSMutableArray *exceptions = [[NSMutableArray alloc] initWithArray:rule[@"exceptions"]];
    
    valueArray = [NSMutableArray arrayWithArray:[valueArray valueForKey:@"lowercaseString"]];
    exceptions = [NSMutableArray arrayWithArray:[exceptions valueForKey:@"lowercaseString"]];
    
    // Remove all the exceptions
    [valueArray removeObjectsInArray:exceptions];
    
    // If the array still has a value after the exceptions have been removed then generate the reminder
    if ([valueArray count] > 0) {
        return YES;
    }
    
    return NO;
}

/**
 *  @author Kevin O  Sullivan
 *  
 *  Tests if an json array of values contains a value. This method accepts key called triggers which should an array of values to check for. This method also accepts a key "exception" which is an array of values to ignore.
 *
 *  @param rule  The rule to test against
 *  @param value The value
 *
 *  @return returns true if a reminder should be generated
 */
-(BOOL)testArrayContainsRule:(NSDictionary *)rule forValue:(id)value{
    
    if (!value) {
        return NO;
    }
    
    NSMutableArray *valueArray = [[Utilities sharedInstance] jsonArrayToMutableArray:value];
    NSMutableArray *triggers = [[NSMutableArray alloc] initWithArray:rule[@"triggers"]];
    NSMutableArray *exceptions = [[NSMutableArray alloc] initWithArray:rule[@"exceptions"]];
    
    valueArray = [NSMutableArray arrayWithArray:[valueArray valueForKey:@"lowercaseString"]];
    triggers = [NSMutableArray arrayWithArray:[triggers valueForKey:@"lowercaseString"]];
    exceptions = [NSMutableArray arrayWithArray:[exceptions valueForKey:@"lowercaseString"]];
    
    // Remove all the exceptions
    [valueArray removeObjectsInArray:exceptions];
    
    // Check if values given contains any of the triggers. If is does return YES to generate reminder
    for (id trigger in triggers) {
        if ([valueArray containsObject:trigger]) {
            return YES;
        }
    }
    
    return NO;
}

 /**
  *  @author Kevin O  Sullivan
  *  
  *  Check if the age of a given date is older, in days, than a number specified in the trggier key in the given rule.
  *
  *  @param rule  The rule to tests against
  *  @param value The value
  *
  *  @return returns true if a reminder should be generated
  */

-(BOOL)testDaysOlderThanTodayRule:(NSDictionary *)rule forValue:(id)value{
    
    if (!value) {
        return NO;
    }
    
    NSInteger trigger = [rule[@"trigger"] integerValue];
    
    NSDate *dateToTest = (NSDate *)value;
    NSDate *now = [NSDate date];
    
    NSTimeInterval interval = [now timeIntervalSinceDate:dateToTest];
    
    int intervalInDays = interval / 60.0 / 60.0 /24.0;
    
    if(intervalInDays >= trigger){
        return YES;
    }
    else{
        return NO;
    }
}

 /**
  *  @author Kevin O  Sullivan
  *  
  *  Checks if a string is present and has a length greater than 0.
  *
  *  @param rule  The rule to tests against
  *  @param value The value
  *
  *  @return returns true if a reminder should be generated
  */
-(BOOL)testStringWithValueRule:(NSDictionary *)rule forValue:(id)value{
    
    if (!value) {
        return NO;
    }
    
    NSInteger length = [(NSString *)value length];
    
    if(value != NULL && length > 0){
        return YES;
    }
    else{
        return NO;
    }
}

/**
  *  @author Kevin O  Sullivan
  *  
  *  Checks if a NSSet contains any objects
  *
  *  @param rule  The rule to tests against
  *  @param value The value
  *
  *  @return returns true if a reminder should be generated
  */
-(BOOL)testSetHasObjectsRule:(NSDictionary *)rule forValue:(id)value{
    
    if (!value) {
        return NO;
    }
    
    NSInteger length = [(NSSet *)value count];
    
    if(value != NULL && length > 0){
        return YES;
    }
    else{
        return NO;
    }
}


 /**
  *  @author Kevin O  Sullivan
  *  
  *  Reads the json file containing all the rules need to check the NPN.
  *
  *  @return Returns an NSDicitonary representation of the rules.
  */

-(NSDictionary *)readNpnReminderRules{
    NSString *businessRulesPath = [[NSString alloc] initWithFormat:@"%@/NpnReminderRules.json", [[NSBundle mainBundle] resourcePath]];
    NSData *data = [NSData dataWithContentsOfFile:businessRulesPath];
    NSError *error;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&error];
    
    return json;
}

#pragma mark -
#pragma mark Core Data
- (NSManagedObjectContext *)managedObjectContext {
    
    RKManagedObjectStore *store = [[VenusCoreDataModel sharedDataModel] objectStore];
    NSManagedObjectContext *context = [store mainQueueManagedObjectContext];
    
    return context;
    
}

#pragma mark - 
#pragma mark Reminder Fields

-(NSDictionary *)getNPNReminderFieldsSchema{
    NSDictionary *dict =@{
        @"vitals_temperature":@{
               @"section": @"vitals",
               @"field_title": @"Temperature",
               @"field_type": @"string"
            },
        @"vitals_pulse_rate":@{
               @"section": @"vitals",
               @"field_title": @"Pulse",
               @"field_type": @"string"
            },
        @"vitals_respiration_rate":@{
               @"section": @"vitals",
               @"field_title": @"Resp. Rate",
               @"field_type": @"string"
            },
        @"vitals_blood_pressure_systolic":@{
               @"section": @"vitals",
               @"field_title": @"BP Systolic",
               @"field_type": @"string"
            },
        @"vitals_blood_pressure_diastolic":@{
               @"section": @"vitals",
               @"field_title": @"BP Diastolic",
               @"field_type": @"string"
            },
        @"vitals_o2_saturation":@{
               @"section": @"vitals",
               @"field_title": @"O2 Sat.",
               @"field_type": @"string"
            },
        @"pain_non_pharm_interventions_effective":@{
               @"section": @"pain",
               @"field_title": @"Non-pharm. interventions effective",
               @"field_type": @"bool"
            },
        @"pain_meds_effective":@{
                @"section": @"pain",
                @"field_title": @"Meds effective",
                @"field_type": @"bool"
                },
        @"mental_psych_mood_wnl":@{
               @"section": @"mental",
               @"field_title": @"Affect & Mood WNL",
               @"field_type": @"bool"
            },
        @"mental_coping":@{
               @"section": @"mental",
               @"field_title": @"Coping",
               @"field_type": @"bool"
            },
        @"mental_meds_effective":@{
               @"section": @"mental",
               @"field_title": @"Meds. effective",
               @"field_type": @"bool"
            },
        @"cardio_chest_pain":@{
               @"section": @"cardio",
               @"field_title": @"Chest pain",
               @"field_type": @"multiselect"
            },
        @"cardio_edema":@{
               @"section": @"cardio",
               @"field_title": @"Edema",
               @"field_type": @"bool"
            },
        @"cardio_pedal":@{
               @"section": @"cardio",
               @"field_title": @"Pedal pulses",
               @"field_type": @"string"
            },
        @"cardio_meds_effective":@{
               @"section": @"cardio",
               @"field_title": @"Meds effective",
               @"field_type": @"bool"
            },
        @"pulm_laboured_description":@{
               @"section": @"pulmonary",
               @"field_title": @"Labored description",
               @"field_type": @"string"
            },
        @"pulm_cough_productive_type":@{
               @"section": @"pulmonary",
               @"field_title": @"Cough productive type",
               @"field_type": @"string"
            },
        @"pulm_dyspnea":@{
               @"section": @"pulmonary",
               @"field_title": @"Dyspnea",
               @"field_type": @"string"
               },
        @"pulm_ss_infection_noted":@{
               @"section": @"pulmonary",
               @"field_title": @"S/S infection noted",
               @"field_type": @"bool"
            },
        @"pulm_ss_antibiotic_init":@{
               @"section": @"pulmonary",
               @"field_title": @"S/S antibiotic init.",
               @"field_type": @"bool"
            },
        @"pulm_meds_effective":@{
               @"section": @"pulmonary",
               @"field_title": @"Meds effective",
               @"field_type": @"bool"
            },
        @"gigu_last_24_urinary_output":@{
               @"section": @"GU",
               @"field_title": @"Urinary output",
               @"field_type": @"string"
            },
        @"gigu_urine_color":@{
               @"section": @"GU",
               @"field_title": @"urine color",
               @"field_type": @"string"
            },
        @"gigu_urine_odor":@{
               @"section": @"GU",
               @"field_title": @"urine odor",
               @"field_type": @"string"
            },
        @"gigu_ua_obtained":@{
               @"section": @"GU",
               @"field_title": @"UA obtained",
               @"field_type": @"bool"
               },
        @"gigu_ss_uti":@{
                @"section": @"GU",
                @"field_title": @"S/S UTI",
                @"field_type": @"bool"
                },
        @"gigu_antibiotic_initiated":@{
                @"section": @"GU",
                @"field_title": @"S/S UTI antibiotic init.",
                @"field_type": @"bool"
                },
        @"gigu_appetite":@{
               @"section": @"GI",
               @"field_title": @"appetite",
               @"field_type": @"string"
            },
        @"gigu_fluid_intake":@{
               @"section": @"GI",
               @"field_title": @"fluid intake",
               @"field_type": @"string"
            },
        @"gigu_gi_issues":@{
               @"section": @"GI",
               @"field_title": @"GI issues",
               @"field_type": @"multiselect"
            },
        @"gigu_abdomen":@{
               @"section": @"GI",
               @"field_title": @"Abdomen",
               @"field_type": @"multiselect"
            },
        @"ascites":@{
               @"section": @"GI",
               @"field_title": @"ascites",
               @"field_type": @"bool"
            },
        @"gigu_last_bowel_movement":@{
               @"section": @"GI",
               @"field_title": @"Last BM",
               @"field_type": @"date"
            },
        @"gi_bowel_meds_interventions":@{
               @"section": @"GI",
               @"field_title": @"Meds/Interventions",
               @"field_type": @"multiselect"
            },
        @"gi_bowel_meds_interventions_effective":@{
               @"section": @"GI",
               @"field_title": @"Meds Effective",
               @"field_type": @"bool"
            },
        @"musculoskeletal_high_risk_for_fall":@{
               @"section": @"musculoskeletal",
               @"field_title": @"High risk for fall",
               @"field_type": @"bool"
            },
        @"musculoskeletal_fall_since_last_visit":@{
               @"section": @"musculoskeletal",
               @"field_title": @"Fall since last visit",
               @"field_type": @"bool"
            },
        @"musculoskeletal_meds_effective":@{
                @"section": @"musculoskeletal",
                @"field_title": @"Meds Effective",
                @"field_type": @"bool"
                },
        @"skin_color":@{
               @"section": @"integumentary",
               @"field_title": @"Skin color",
               @"field_type": @"string"
            },
        @"endocrine_fsbs":@{
                @"section": @"endocrine",
                @"field_title": @"FSBS (mg/dL)",
                @"field_type": @"string"
            },
        @"endocrine_meds_effective":@{
                @"section": @"endocrine",
                @"field_title": @"Meds Effective",
                @"field_type": @"bool"
            },
        @"decline_symptoms_out_of_control":@{
                @"section": @"decline",
                @"field_title": @"Symtoms out of control",
                @"field_type": @"bool"
            },
        @"coping":@{
                @"section": @"coping",
                @"field_title": @"Coping",
                @"field_type": @"multiselect"
            },
        @"teaching_medications":@{
                @"section": @"support",
                @"field_title": @"Medications",
                @"field_type": @"string"
            },
        @"teaching_disease_process":@{
                @"section": @"support",
                @"field_title": @"Disease process",
                @"field_type": @"string"
            },
        @"teaching":@{
                @"section": @"support",
                @"field_title": @"Other Teachings",
                @"field_type": @"multiselect"
            },
        @"current_treatment_appropriate":@{
            @"section": @"wounds",
            @"field_title": @"Current treatment appropriate",
            @"field_type": @"bool"
          },
        @"ss_infection":@{
            @"section": @"wounds",
            @"field_title": @"S/S infection noted",
            @"field_type": @"bool"
          },
        @"antibiotic_initiated":@{
            @"section": @"wounds",
            @"field_title": @"S/S antibiotic init.",
            @"field_type": @"bool"
          },
        @"breath_sounds":@{
            @"section": @"pulmonary",
            @"field_title": @"Breath Sounds",
            @"field_type": @"ns_set"
          }
    };
    return dict;
}
@end
