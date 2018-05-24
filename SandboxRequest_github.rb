require 'typhoeus'
require 'json'
require 'csv'

#The following script will scan the source data for requests teacher's make for sandbox courses.

#The script will do the following:

#1. Create a course, move it to the appropriate sub-account.
#2. Find the users SIS ID using their login ID.
#3. Enroll them in the course they requested as a teacher.

#=================================
#ENVIRONMENT VALUES
#=================================


canvas_url = '' #Points to Canvas Environment
canvas_token = '' #Token
request_source = '' #Data source that contains course requests

course_term = '' #We have a sub-account just for sandbox courses, and this is it.
course_enrollment_term = '' #The most current term, in this case the 18-19 school year.

enrollment_data = Array.new #This array will house the user's SIS id and the 
                            #course ID we created for them.

CSV.foreach(request_source, headers: true) do |row|
  
  course_name = row['Course Name'] != nil ? row['Course Name'] : "Untitled" 
  #Use a tertiary to check for a Course Name. If no name is present, provide one.
  course_code = course_name.split.first 
  #Separate the course_name into the first complete word as the course code. For example if the requested course is Biology Period 4, this will list the short name as 'Biology'.
  course_owner = row['Email Address'][/[^@]+/] 
  #Teachers may have an @nths or @newtrier email domain, but both may not be listed in their user profile. Using ReGeX, we pull out everything from the '@' sign forward and keep the login id.
  
  
  #Set up the API call with all the necessary variables
  create_course = Typhoeus::Request.new(
  "#{canvas_url}/api/v1/accounts/self/courses",
  method: :post,
  headers: { authorization: "Bearer #{canvas_token}"},
  params: {
    "course[name]" => course_name,
    "course[course_code]" => course_code,
    "course[account_id]" => course_term,
    "course[enrollment_term_id]" => course_enrollment_term
  }
  )
  
  create_course.on_complete do |response|
    if response.code == 200
      data = JSON.parse(response.body)
      #Push to the array the email address and the course ID we created for that user 
      enrollment_data << [course_owner, data['id']]
    else
      puts "Error #{response.code} encountered. Please check the data and try again."
    end
  end
      
  create_course.run #Run the API call.
end

#Assuming there were no issues, we now have an array with both the owner of the course and the Sandbox course
#we created for them. We're going to search by login ID to get their SIS ID and replace that variable before we enroll them.
enrollment_data.each do |row|
  
  #Setting up a Search API call  
  find_user = Typhoeus::Request.new(
    "#{canvas_url}/api/v1/accounts/self/users",
    method: :get,
    headers: { authorization: "Bearer #{canvas_token}"},
    params: {
      "search_term" => row[0]
    }
    )  
    
    find_user.on_complete do |response|
      if response.code == 200
        data = JSON.parse(response.body)
        row[0] = data.first['id'] #Replace the login id with SIS id in the array.
        #We use '.first' simply because the array only has a length of 1 (ie. The search should only return one user, hopefully.)
      end        
    end
  find_user.run #Find me that user and get that SIS ID.  
  
  #Setting up the enrollment
  enroll_user = Typhoeus::Request.new(
  "#{canvas_url}/api/v1/courses/#{row[1]}/enrollments", #Make the call to the right course we created for the user
  method: :post,
  headers: { authorization: "Bearer #{canvas_token}"},
  params: {
    "enrollment[user_id]" => row[0], #Use the SIS ID
    "enrollment[type]" => 'TeacherEnrollment', #Enroll them as a teacher
    "enrollment[enrollment_state]" => 'active' #Set them as active
  }
  )
  
  enroll_user.on_complete do |response|
    if response.code == 200
      puts "The course #{row[1]} has been created and updated successfully."
    else
      puts "#{canvas_url}/api/v1/courses/#{row[1]}/enrollments"
      puts "#{response.code}"
    end
  end
  
  enroll_user.run #Update the course enrollment
  
end