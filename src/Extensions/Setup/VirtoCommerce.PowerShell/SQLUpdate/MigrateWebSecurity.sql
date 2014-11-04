INSERT INTO [AspNetUsers]
(Id, UserName, EmailConfirmed, PhoneNumberConfirmed, TwoFactorEnabled, PasswordHash, SecurityStamp, AccessFailedCount, LockoutEndDateUtc, LockoutEnabled) 
SELECT UserId, a.UserName, IsConfirmed, 0, 0, Password, PasswordSalt, PasswordFailuresSinceLastSuccess, LastPasswordFailureDate, 
CASE WHEN a.RegisterType = 2 THEN 1 ELSE 0 END
FROM [webpages_Membership] m INNER JOIN [Account] a on a.AccountId = m.UserId

