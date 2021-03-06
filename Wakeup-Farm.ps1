<#
.SYNOPSIS
	Warmup a SharePoint farm.

.DESCRIPTION
	Warmup a SharePoint farm. For Publishing webs, the individual pages are loaded to warmup all pages and minimize
	the time which is needed to load those pages. Since publishing pages are using the output cache, it might be wise to 
	schedule this script on each WFE in a farm to cache all pages on all WFE's. Additionally, provide all hostheaders of
	the webapplications in the hosts file of each WFE and have them point to the local server. This way we are sure the
	script will not target the load balancer.

.NOTES
	File Name: Wakeup-Farm.ps1
	Author   : Bart Kuppens - CTG Belgium
	Version  : 1.3
#>

Add-Type -TypeDefinition @"
   public enum LogType
   {
      INFO,
      ERROR
   }
"@

###############################################################################
# FUNCTIONS                                                                   #
###############################################################################

function Write-Log([string]$message, [LogType]$MessageType)
{
    $TimeStamp = $([DateTime]::Now.ToString('yyyy/MM/dd HH:mm:ss'))
    $message = "$TimeStamp - $MessageType : $message"
    Out-File -InputObject $message -FilePath $LogFile -Append
}

function Cleanup-Logs
{
	$cleanupDate = (Get-Date).AddDays(-15)
	Get-ChildItem -Path $ScriptLogLocation -Filter "wakeup*.log" | ? {$_.CreationTime -lt $cleanupDate} | Remove-Item -Force -Confirm:$false
}

function Get-Webpage([string]$url, [System.Net.NetworkCredential]$cred=$null)
{
    $error = $false
    $webRequest = [System.Net.HttpWebRequest]::Create($url)
	$webRequest.UserAgent = "Mozilla/5.0 (Windows; U; Windows NT 5.1; zh-TW; rv:1.9.2.12) Gecko/20101026 Firefox/3.6.12 GTB7.1 ( .NET CLR 3.5.30729)"
	$webRequest.Accept = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
    $webRequest.Timeout = 300000
    if($cred -eq $null)
    {
        $webRequest.Credentials = [system.Net.CredentialCache]::DefaultCredentials 
    }
    try 
    {
        $res = $webRequest.getresponse()
        Write-Log -Message "Waking up site $url : Success - Status was $($res.StatusCode)" -MessageType INFO 
    }
    catch
    {
        Write-Log -Message "Waking up site $url : Failure - $($_.Exception.InnerException.Message)" -MessageType ERROR 
    }
}

###############################################################################
# FUNCTIONS                                                                   #
###############################################################################

$ScriptLogLocation = "c:\scriptlog"

# Load the SharePoint PowerShell snapin if needed
if ((Get-PSSnapin -Name Microsoft.SharePoint.PowerShell -ErrorAction SilentlyContinue) -eq $null)
{
	Add-PSSnapin Microsoft.SharePoint.PowerShell
}

# Cleanup old logs
Cleanup-Logs

$LogFile = "$ScriptLogLocation\Wakeup_" + $([DateTime]::Now.ToString('yyyyMMdd_HHmmss')) + ".log"
$Webapps = Get-SPWebApplication
$Array = @()
$i = 0
foreach ($webapp in $Webapps)
{
    $Sites = Get-SPSite -Webapplication $webapp -Limit All
    foreach ($site in $Sites)
    {
        try
        {
            $site.AllWebs | ? {$_.AppInstanceId -eq [System.Guid]::Empty} | % {
                try
                {
                    if ([Microsoft.SharePoint.Publishing.PublishingWeb]::IsPublishingWeb($_))
    				{
    					$pubweb = [Microsoft.SharePoint.Publishing.PublishingWeb]::GetPublishingWeb($_)
                        $pages = $pubweb.GetPublishingPages()
    					foreach ($page in $pages)
    					{
                            if ($page.ListItem.HasPublishedVersion)
                            {
                                $currentUrl = [Microsoft.SharePoint.Utilities.SPUrlUtility]::CombineUrl($pubweb.Uri.AbsoluteUri,$page.Url)
                                $i++
                                $Array = $Array + $currentUrl
                            }
    					}
    				}
                    else
                    {
                        $currentUrl = $_.Url
                        $Array = $Array + $currentUrl
                        $i++
                    }
                }
                catch {}
                finally { $_.Dispose() }
            }
        }
        catch { }
        finally { $site.Dispose() }
    }
}

Write-Log -Message "Discovered $i URL's. Proceeding with the warmup." -MessageType INFO
$Array | % { Get-WebPage -url $_ -cred $cred }

