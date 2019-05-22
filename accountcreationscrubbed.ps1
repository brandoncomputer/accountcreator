set-alias run invoke-expression
$global:fieldsep = "|"

$ErrorActionPreference = "SilentlyContinue"

$sqlServer = ""
$sqlUser = "sa"
$sqlPassword = ""
$sqlDb = "cohauth"

$global:userId = 1

function Get-Adler32 {
    param(
        [string] $data
    )

    $mod_adler = 65521
    $a = 1
    $b = 0
    $len = $data.Length
    for ($index = 0; $index -lt $len; $index++) {
        $a = ($a + [byte]$data[$index]) % $mod_adler
        $b = ($b + $a) % $mod_adler
    }

    return ($b -shl 16) -bor $a;
}

function Get-HashedPassword {
    param(
        [string] $UserName, 
        [string] $Password
    )
        $a32 = adler32($UserName.ToLower())
        $a32hex = $a32.ToString("x8")
        $a32hex = $a32hex.Substring(6, 2) + $a32hex.Substring(4, 2) + $a32hex.Substring(2, 2) + $a32hex.Substring(0, 2)
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Password + $a32hex)
        $digest = [System.Security.Cryptography.HashAlgorithm]::Create("SHA512").ComputeHash($bytes)
        return $digest
}

function Get-Connection {
    $connection = [System.Data.SqlClient.SqlConnection]::new()
    $connection.ConnectionString = "Server='$sqlServer';Database='$sqlDb';User Id='$sqlUser';Password='$sqlPassword';"
    $connection.Open()
	
	$command = [System.Data.SqlClient.SqlCommand]::new()
    $command.Connection = $Connection
    $command.CommandText = "SELECT COUNT(*) FROM user_account;"
    $userID = $command.ExecuteScalar()
	$global:userID = $(succ $userID)
    $command.Dispose()
		
    return $connection
}

function Set-UserAccount {
    param(
        [System.Data.SqlClient.SqlConnection] $Connection,
        [string] $UserName,
        [int] $UserId,
        [int] $ForumId,
		[string] $first_name,
		[string] $last_name,
		[string] $email
    )

    $command = [System.Data.SqlClient.SqlCommand]::new()
    $command.Connection = $Connection
    $command.CommandText = "INSERT INTO user_account (account, uid, forum_id, pay_stat, first_name, last_name, email) VALUES (@UserName, @UserId, @ForumId, 1014, @first_name, @last_name, @email);"
    $command.Parameters.AddWithValue("@UserName", $UserName) > $null
    $command.Parameters.AddWithValue("@UserId", $UserId) > $null
    $command.Parameters.AddWithValue("@ForumId", $ForumId) > $null
	$command.Parameters.AddWithValue("@first_name", $first_name) > $null
	$command.Parameters.AddWithValue("@last_name", $last_name) > $null
	$command.Parameters.AddWithValue("@email", $email) > $null
    $command.ExecuteScalar()
    $command.Dispose()
}

function Set-UserAuth {
    param(
        [System.Data.SqlClient.SqlConnection] $Connection,
        [string] $UserName,
        [byte[]] $HashedPassword
    )

    $p = ""
    foreach($byte in $hashedPassword) {
        $p = $p + $byte.ToString("x2");
    }

    $command = [System.Data.SqlClient.SqlCommand]::new()
    $command.Connection = $Connection
    $command.CommandText = "INSERT INTO user_auth (account, password, salt, hash_type) VALUES (@UserName, CONVERT(BINARY(128), '$p'), 0, 1);"
    $command.Parameters.AddWithValue("@UserName", $UserName) > $null
    # Using AddWithValue for the password results in extra bytes being added to the string for some reason?
    # In a rush, so hack it for now
    #$command.Parameters.AddWithValue("@Password", $HashedPassword)
    #$command.Parameters.AddWithValue("@Password", $p)
    $command.ExecuteScalar()
    $command.Dispose()
}

function Set-UserData {
    param(
        [System.Data.SqlClient.SqlConnection] $Connection,
        [string] $UserId
    )

    $command = [System.Data.SqlClient.SqlCommand]::new()
    $command.Connection = $Connection
    $command.CommandText = "INSERT INTO user_data (uid, user_data) VALUES (@UserId, 0x0080C2E000D00B0C000000000CB40058);"
    $command.Parameters.AddWithValue("@UserId", $UserId) > $null
    $command.ExecuteScalar()
    $command.Dispose()
	
	$command = [System.Data.SqlClient.SqlCommand]::new()
    $command.Connection = $Connection
    $command.CommandText = "INSERT INTO user_server_group (uid, server_group_id) VALUES (@UserId, 1);"
    $command.Parameters.AddWithValue("@UserId", $UserId) > $null
    $command.ExecuteScalar()
    $command.Dispose()
}

function Set-User {
    param(
        [string] $UserName,
        [string] $Password,
		[string] $first_name,
		[string] $last_name,
		[string] $email
    )

    $hashedPassword = Get-HashedPassword -UserName $UserName -Password $Password

    $connection = Get-Connection
    Set-UserAccount -Connection $connection -UserName $UserName -UserId $UserId -ForumId $UserId -first_name $first_name -last_name $last_name -email $email
    Set-UserAuth -Connection $connection -UserName $UserName -HashedPassword $hashedPassword
    Set-UserData -Connection $connection -UserId $UserId
    $connection.Dispose()
}

function len($a) {
   return $a.length
<#
   .SYNOPSIS
   Returns the length of a string
    
   .DESCRIPTION
    VDS
   $length = $(len $textbox1.text)
    
   .LINK
   https://dialogshell.com/vds/help/index.php/len
#>
}

function server ($a,$b,$c){
   switch ($a) {
       start {
           $vdsServer = New-Object Net.HttpListener
           $server = $b + ':' + $c + '/'
           $vdsServer.Prefixes.Add($server)
           $vdsServer.Start()
           return $vdsServer
       }
       watch {
           $event = $b.GetContext()
           return $event
       }
       context {
           return $b.Request.Url.LocalPath
       }
       return {
           $buffer = [System.Text.Encoding]::ASCII.GetBytes($c)
           $b.Response.ContentLength64 = (len $buffer)
           $b.Response.OutputStream.Write($buffer, 0, (len $buffer))
           $b.Response.Close()
       }
       stop {
           $b.Stop()
       }
   }
<#
   .SYNOPSIS
   Controls web server transactions
    
   .DESCRIPTION
    VDS
   $vdsServer = server start http://localhost:2323
   $event = (server watch $vdsServer)
   if(equal (server context $event) "/")
   server return $event $return
   server stop $vdsServer

   .LINK
   https://dialogshell.com/vds/help/index.php/server
#>
}

function succ($a) {
   return $a + 1
<#
   .SYNOPSIS
    Adds one to a value.
    
   .DESCRIPTION
    VDS
   $increase = $(succ $number)
   
   .LINK
   https://dialogshell.com/vds/help/index.php/succ
#>
}

function equal($a, $b) {
   if ($a -eq $b) {
       return $true 
   } 
   else {
       return $false
   }
<#
   .SYNOPSIS
   Returns if two values are equal.
    
   .DESCRIPTION
    VDS
    if ($(equal 4 2))
    {console "Hey, four and two really are equal!"}
    
   .LINK
   https://dialogshell.com/vds/help/index.php/equal
#>
}

function substr($a,$b,$c) {
   return $a.substring($b,($c-$b))
<#
   .SYNOPSIS
    Gets the value of a string between a start index and a end index
    
   .DESCRIPTION
    VDS
   $string = $(substr $string 3 6)
   
   .LINK
   https://dialogshell.com/vds/help/index.php/substr
#>
}

function string($a) {
return ($a | Out-String).trim()

#rant sparse version. Click .link below for rant. I'm actually quite crazy sometimes.

<#
   .SYNOPSIS
    Converts a value to string.
    
   .DESCRIPTION
    VDS
   $string = $(string $value)
   
   .LINK
   https://dialogshell.com/vds/help/index.php/string
#>
}

function parse ($a) {
   return $a.split($global:fieldsep)
<#
   .SYNOPSIS
   parses a string by fieldsep
    
   .DESCRIPTION
    VDS
   $parse = $(parse $string)
   info $parse[0]
   
   .LINK
   https://dialogshell.com/vds/help/index.php/parse
#>
}

$port = 7777

#start server
$vdsServer = server start "http://+" $port

#recall server name
$server = 'http://localhost:' + $port + '/'

#launch gui window
#run "start $server"
run "mshta $server"

    #do it until the program ends.
    while(1){
    
        #wait event
        $event = (server watch $vdsServer)
        
        #event - "/" is basically evloop. It's asking for the GUI content.
        if(equal (server context $event) "/") {
        
            #prepare return for client
            $return = @"
            <title>Account Creation</title>
            <body>
			<font size=5>Account Registration</font><br>
			<table>
			<td>First Name<br><input id=first></td>
			<td>Last Name<br><input id=last></td></td>
			<tr>
			<td colspan=2>
			Email<br><input id=email size=40></td>
			</td>
			<tr>
			<td>
			Username<br>
            <input id=username maxlength=14>
			</td>
			<td>
			Password<br>
            <input type=password id=password>
			</td>
			</table>
			Allow 10 seconds after submitting, you will get a confirmation when completed.
            <br>
            <!--The button sends the run request to frameUs-->
            <button onclick="myFunction()" style="vertical-align: top">Create Account</button>
			            <div id=txt1></div>

            <script>
                function myFunction() {
                //  frameUs location becomes the client request and is read by the server wait event. 
                //  frameUs will send the contents of txt1 to the server and will contain the result from the server when the request is complete.
                frameUs.location.href = '$server' + username.value + "|" + password.value + "|" + first.value + "|" + last.value + "|" + email.value;
                    // It takes time for the server to fill the request result, so we can't update immediately.
                    timerx = setTimeout(myTimer, 10000)
                }
                function myTimer() {
                    // Update the server return result from frameUs back into txt1
                    var x          = document.getElementById('frameUs');
                    var doc        = x.contentDocument? x.contentDocument: x.contentWindow.document;
                    txt1.innerHTML = doc.body.innerHTML;
                    // Stop ticking.
                    window.clearTimeout(timerx)
                }
            </script>
            <iframe name=frameUs id=frameUs style='visibility:hidden'></iframe>
"@
        }
        else {
            #Get the event request.
            $result = (server context $event)
                
            $result = $(string $result)

            $parse = $(substr $result 1 $(len $result))
                        
            $parse = parse $parse
            
            $userName 		= $parse[0]
			$userPassword 	= $parse[1]
			$first_name1 	= $parse[2]
			$last_name1 	= $parse[3]
			$email1 		= $parse[4]
            
            #prepare the return
            $return = "<body>Account created! Start City of Heroes and log in with your account details.</body>"
        }
        #return the result back to the client.
        server return $event $return
        
		if ($parse -ne $null)
		{
		Set-User -UserName $userName -Password $userPassword -first_name $first_name1 -last_name $last_name1 -email $email1
		}	
		
    }
    #stop the server
server stop $vdsServer
